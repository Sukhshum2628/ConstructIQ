# ConstructIQ - Firestore Database Structure

This document outlines the NoSQL schema used in the ConstructIQ project. The database follows a hierarchical structure with root collections and nested sub-collections for project-specific data.

---

## 1. Root Collections

### `users`
Stores authenticated user profiles and their roles.
- **Path**: `/users/{uid}`
- **Fields**:
  - `uid`: String (Document ID)
  - `name`: String
  - `email`: String
  - `role`: String (enum: `admin`, `manager`, `engineer`, `owner`)
  - `phone`: String? (Optional)
  - `designation`: String? (Optional)
  - `assignedProjects`: List<String> (Array of project IDs)
  - `assignedProjectId`: String? (Specific to Owners)
  - `createdAt`: Timestamp
  - `lastLogin`: Timestamp

### `projects`
Stores high-level details of construction projects.
- **Path**: `/projects/{projectId}`
- **Fields**:
  - `projectId`: String (Document ID)
  - `name`: String
  - `location`: String
  - `startDate`: Timestamp
  - `expectedEndDate`: Timestamp
  - `originalEndDate`: Timestamp? (Stored if project is extended)
  - `status`: String (enum: `planning`, `active`, `completed`, `onhold`, `closed`)
  - `createdBy`: String (UID)
  - `teamMembers`: List<String> (Array of UIDs)
  - `plannedBudget`: Double
  - `projectType`: String
  - `cadFileUrl`: String (Firebase Storage link)
  - `estimationStatus`: String (enum: `pending`, `processing`, `completed`, `failed`)
  - `durationDays`: Int
  - `totalWallLength`: Double
  - `totalFloorArea`: Double
  - `floorCount`: Int
  - `createdAt`: Timestamp
  - `ownerUserId`: String?

### `workforce`
A general pool of workers that can be assigned to projects.
- **Path**: `/workforce/{workerId}`
- **Fields**:
  - `id`: String (Document ID)
  - `name`: String
  - `trade`: String (enum: `mason`, `laborer`, `helper`, `carpenter`, `electrician`, `plumber`, `fitter`, `steelFixer`)
  - `contact`: String?
  - `status`: String (enum: `active`, `inactive`)
  - `assignedProjectId`: String
  - `dailyRate`: Double?

---

## 2. Project Sub-collections
These collections are nested under `/projects/{projectId}/`.

### `estimates`
AI-generated material and labor estimates derived from CAD/DXF analysis.
- **Path**: `/projects/{projectId}/estimates/{estimateId}`
- **Fields**:
  - `estimateId`: String
  - `generatedAt`: Timestamp
  - `cadFileName`: String
  - `geometryData`: Map<String, Double> (e.g., `{"totalWallLength": 45.5, ...}`)
  - `estimatedMaterials`: Map<String, Map<String, Dynamic>> (Material breakdown with quantities and rates)
  - `confidence`: String (enum: `high`, `medium`, `low`)
  - `labour`: Map<String, Dynamic>?
  - `totalLabourDays`: Int?
  - `assumptions`: List<String>? (AI engineering assumptions)
  - `disclaimer`: String?

### `deviations`
AI/ML detected deviations between projected estimates and actual daily logs.
- **Path**: `/projects/{projectId}/deviations/{deviationId}`
- **Fields**:
  - `deviationId`: String
  - `projectId`: String
  - `deviationPct`: Double
  - `zScore`: Double (Statistical anomaly score)
  - `flagged`: Boolean
  - `overallSeverity`: String
  - `mlOverrunProbability`: Double
  - `aiInsightSummary`: String
  - `breakdown`: Map<String, Dynamic> (Detailed material-wise deviation)
  - `createdAt`: Timestamp

### `resourceLogs`
Daily progress reports submitted by site engineers.
- **Path**: `/projects/{projectId}/resourceLogs/{logId}`
- **Fields**:
  - `id`: String
  - `projectId`: String
  - `loggedBy`: String (UID)
  - `date`: Timestamp
  - `materialUsage`: Map<String, Double>
  - `equipment`: List<Map<String, Dynamic>> (Hours used/idle per machine)
  - `laborHours`: Double
  - `notes`: String
  - `weatherCondition`: String
  - `isWeatherDelay`: Boolean
  - `photoUrl`: String? (Link to site photo)
  - `location`: Map<String, Double>? (GPS coordinates)
  - `createdAt`: Timestamp

### `vendorBills`
Metadata for bills and invoices uploaded for material procurement.
- **Path**: `/projects/{projectId}/vendorBills/{billId}`
- **Fields**:
  - `id`: String
  - `projectId`: String
  - `vendorName`: String
  - `amount`: Double
  - `date`: Timestamp
  - `category`: String
  - `fileUrl`: String (Firebase Storage link)
  - `uploadedBy`: String (UID)
  - `items`: List<Map<String, Dynamic>> (Line items from bill)
  - `createdAt`: Timestamp

### `delayNotices`
Consensus-based delay reports filed by engineers for team voting.
- **Path**: `/projects/{projectId}/delayNotices/{noticeId}`
- **Fields**:
  - `id`: String
  - `projectId`: String
  - `type`: String (enum: `material_delivery`, `equipment`, `labour`, `other`)
  - `title`: String
  - `description`: String
  - `affectedMaterials`: List<String>
  - `expectedDeliveryDate`: Timestamp
  - `reportedDate`: Timestamp
  - `createdBy`: String (UID)
  - `status`: String (enum: `pending_consensus`, `approved`, `rejected_by_team`, `acknowledged_extended`, ...)
  - `votes`: Map<UID, Map<String, Dynamic>> (Engineer votes and comments)
  - `managerResponse`: Map<String, Dynamic>? (Decision, days extended, and notes)

### `delays`
Verified delay records that officially impact the project timeline.
- **Path**: `/projects/{projectId}/delays/{delayId}`
- **Fields**:
  - `id`: String
  - `projectId`: String
  - `type`: String (enum: `weather`, `materialShortage`, `laborShortage`, ...)
  - `reason`: String
  - `date`: Timestamp
  - `daysLost`: Int
  - `status`: String
  - `recordedBy`: String (UID)
  - `linkedLogId`: String? (Link to resource log that triggered this)
  - `createdAt`: Timestamp

---

## 3. Global Collections (Collection Groups)
Certain collections are queried across all projects using Firestore **Collection Group Queries**:
- `vendorBills`: Used for the Owner Dashboard to show recent bills across multiple projects.
- `deviations`: Used for the Manager Dashboard to monitor anomalies across the entire organization.
