const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

/**
 * Triggered when a new /users/{uid} document is created.
 * Reads the pendingInviteCode field, validates it against /inviteCodes/{code},
 * assigns companyId and role server-side, then clears the pending field.
 * 
 * For company creators (no invite code), assigns role: "admin" and
 * the companyId they created.
 */
exports.onUserRegistered = functions.firestore
  .document("users/{uid}")
  .onCreate(async (snap, context) => {
    const uid = context.params.uid;
    const userData = snap.data();

    // Path A: User is creating a new company (they are the first admin)
    // Identified by: pendingInviteCode is absent AND pendingCompanyId is present
    if (!userData.pendingInviteCode && userData.pendingCompanyId) {
      const companyId = userData.pendingCompanyId;

      // Verify the company document exists and was created by this user
      const companyDoc = await db.collection("companies").doc(companyId).get();
      if (!companyDoc.exists || companyDoc.data().createdBy !== uid) {
        console.error(`Company ${companyId} not found or not owned by ${uid}`);
        await snap.ref.update({
          registrationError: "Company validation failed",
          role: admin.firestore.FieldValue.delete(),
          companyId: admin.firestore.FieldValue.delete(),
        });
        return;
      }

      // Assign admin role server-side
      await snap.ref.update({
        role: "admin",
        companyId: companyId,
        pendingCompanyId: admin.firestore.FieldValue.delete(),
        registrationStatus: "complete",
      });

      // Set Firebase Auth custom claims for this user
      await admin.auth().setCustomUserClaims(uid, {
        role: "admin",
        companyId: companyId,
      });

      console.log(`Admin role assigned to ${uid} for company ${companyId}`);
      return;
    }

    // Path B: User is joining via invite code
    const inviteCode = userData.pendingInviteCode;
    if (!inviteCode) {
      console.log(`User ${uid} has no pending invite code or company — skipping`);
      return;
    }

    // Validate the invite code
    const codeRef = db.collection("inviteCodes").doc(inviteCode);
    const codeDoc = await codeRef.get();

    if (!codeDoc.exists) {
      await snap.ref.update({
        registrationError: "Invalid invite code",
        pendingInviteCode: admin.firestore.FieldValue.delete(),
      });
      return;
    }

    const codeData = codeDoc.data();

    // Check code is still active
    if (!codeData.isActive) {
      await snap.ref.update({
        registrationError: "Invite code is no longer active",
        pendingInviteCode: admin.firestore.FieldValue.delete(),
      });
      return;
    }

    // Check usage limit
    if (codeData.usesSoFar >= codeData.maxUses) {
      await snap.ref.update({
        registrationError: "Invite code has reached maximum uses",
        pendingInviteCode: admin.firestore.FieldValue.delete(),
      });
      return;
    }

    // Check expiry
    if (codeData.expiresAt && codeData.expiresAt.toDate() < new Date()) {
      await snap.ref.update({
        registrationError: "Invite code has expired",
        pendingInviteCode: admin.firestore.FieldValue.delete(),
      });
      return;
    }

    // All checks passed — assign role and companyId server-side
    const batch = db.batch();

    // Update user document
    batch.update(snap.ref, {
      role: codeData.role,
      companyId: codeData.companyId,
      pendingInviteCode: admin.firestore.FieldValue.delete(),
      registrationStatus: "complete",
    });

    // Consume the invite code
    const newUsesSoFar = (codeData.usesSoFar || 0) + 1;
    batch.update(codeRef, {
      usesSoFar: newUsesSoFar,
      isActive: newUsesSoFar < codeData.maxUses,
    });

    await batch.commit();

    // Set Firebase Auth custom claims
    await admin.auth().setCustomUserClaims(uid, {
      role: codeData.role,
      companyId: codeData.companyId,
    });

    console.log(
      `Role ${codeData.role} assigned to ${uid} for company ${codeData.companyId}`
    );
  });

/**
 * Callable function: generateInviteCode
 * Only callable by users with role: "admin" custom claim.
 * Creates a new invite code document in /inviteCodes/{code}.
 */
exports.generateInviteCode = functions.https.onCall(async (data, context) => {
  // Verify caller is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Must be authenticated to generate invite codes"
    );
  }

  // Verify caller has admin role via custom claims
  const claims = context.auth.token;
  if (claims.role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only admins can generate invite codes"
    );
  }

  const { role, maxUses = 1, expiresInDays = null } = data;

  // Validate role
  const validRoles = ["manager", "engineer", "owner"];
  if (!validRoles.includes(role)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `Role must be one of: ${validRoles.join(", ")}`
    );
  }

  // Generate code like XKQM-7B3N-P2WR
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const generateSegment = () =>
    Array.from({ length: 4 }, () =>
      chars[Math.floor(Math.random() * chars.length)]
    ).join("");
  const code = `${generateSegment()}-${generateSegment()}-${generateSegment()}`;

  const companyId = claims.companyId;

  const codeData = {
    companyId: companyId,
    role: role,
    createdBy: context.auth.uid,
    maxUses: maxUses,
    usesSoFar: 0,
    isActive: true,
    expiresAt: expiresInDays
      ? admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000)
        )
      : null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection("inviteCodes").doc(code).set(codeData);

  console.log(`Invite code ${code} created by ${context.auth.uid}`);

  return { code, role, companyId, maxUses };
});

/**
 * Phase 2+: Set user role in Firebase Auth custom claims.
 * Triggered manually by Admin via callable function.
 */
exports.setUserRole = functions.https.onCall(async (data, context) => {
  if (!context.auth || context.auth.token.role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only admins can manually assign roles"
    );
  }

  const { uid, role } = data;
  const validRoles = ["admin", "manager", "engineer", "owner"];
  if (!validRoles.includes(role)) {
    throw new functions.https.HttpsError("invalid-argument", `Role ${role} is not valid.`);
  }

  try {
    await admin.auth().setCustomUserClaims(uid, { role, companyId: context.auth.token.companyId });
    await db.collection("users").doc(uid).update({ role: role });
    return { status: "success", message: `Role ${role} assigned to user ${uid}` };
  } catch (error) {
    throw new functions.https.HttpsError("internal", error.message);
  }
});
