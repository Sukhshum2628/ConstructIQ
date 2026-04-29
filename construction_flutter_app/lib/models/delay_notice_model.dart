import 'package:cloud_firestore/cloud_firestore.dart';

enum DelayNoticeType { materialDelivery, equipment, labour, other }
enum DelayNoticeStatus {
  pendingConsensus,
  approved,
  rejectedByTeam,
  acknowledgedExtended,
  acknowledgedNoExtension,
  rejectedByManager,
}
enum VoteChoice { agree, disagree }

class VoteEntry {
  final VoteChoice vote;
  final String comment;
  final DateTime votedAt;
  final String engineerName;

  const VoteEntry({
    required this.vote,
    required this.comment,
    required this.votedAt,
    required this.engineerName,
  });

  factory VoteEntry.fromMap(Map<String, dynamic> map) => VoteEntry(
    vote: map['vote'] == 'agree' ? VoteChoice.agree : VoteChoice.disagree,
    comment: map['comment'] as String? ?? '',
    votedAt: (map['votedAt'] as Timestamp).toDate(),
    engineerName: map['engineerName'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'vote': vote == VoteChoice.agree ? 'agree' : 'disagree',
    'comment': comment,
    'votedAt': Timestamp.fromDate(votedAt),
    'engineerName': engineerName,
  };
}

class ManagerResponse {
  final String respondedBy;
  final DateTime respondedAt;
  final String decision;  // 'extend' | 'no_extension' | 'reject'
  final int daysExtended;
  final String managerNote;

  const ManagerResponse({
    required this.respondedBy,
    required this.respondedAt,
    required this.decision,
    required this.daysExtended,
    required this.managerNote,
  });

  factory ManagerResponse.fromMap(Map<String, dynamic> map) => ManagerResponse(
    respondedBy: map['respondedBy'] as String,
    respondedAt: (map['respondedAt'] as Timestamp).toDate(),
    decision: map['decision'] as String,
    daysExtended: (map['daysExtended'] as num? ?? 0).toInt(),
    managerNote: map['managerNote'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'respondedBy': respondedBy,
    'respondedAt': Timestamp.fromDate(respondedAt),
    'decision': decision,
    'daysExtended': daysExtended,
    'managerNote': managerNote,
  };
}

class DelayNotice {
  final String id;
  final String projectId;
  final DelayNoticeType type;
  final String title;
  final String description;
  final List<String> affectedMaterials;
  final DateTime expectedDeliveryDate;
  final DateTime reportedDate;
  final String createdBy;
  final String createdByName;
  final DelayNoticeStatus status;
  final Map<String, VoteEntry> votes;
  final List<String> requiredVoters;
  final DateTime? consensusAt;
  final ManagerResponse? managerResponse;

  const DelayNotice({
    required this.id,
    required this.projectId,
    required this.type,
    required this.title,
    required this.description,
    required this.affectedMaterials,
    required this.expectedDeliveryDate,
    required this.reportedDate,
    required this.createdBy,
    required this.createdByName,
    required this.status,
    required this.votes,
    required this.requiredVoters,
    this.consensusAt,
    this.managerResponse,
  });

  factory DelayNotice.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    DelayNoticeType parseType(String t) => switch (t) {
      'material_delivery' => DelayNoticeType.materialDelivery,
      'equipment'         => DelayNoticeType.equipment,
      'labour'            => DelayNoticeType.labour,
      _                   => DelayNoticeType.other,
    };

    DelayNoticeStatus parseStatus(String s) => switch (s) {
      'approved'                  => DelayNoticeStatus.approved,
      'rejected_by_team'          => DelayNoticeStatus.rejectedByTeam,
      'acknowledged_extended'     => DelayNoticeStatus.acknowledgedExtended,
      'acknowledged_no_extension' => DelayNoticeStatus.acknowledgedNoExtension,
      'rejected_by_manager'       => DelayNoticeStatus.rejectedByManager,
      _                           => DelayNoticeStatus.pendingConsensus,
    };

    final votesMap = (data['votes'] as Map<String, dynamic>? ?? {}).map(
      (uid, voteData) => MapEntry(uid, VoteEntry.fromMap(voteData as Map<String, dynamic>)),
    );

    return DelayNotice(
      id: doc.id,
      projectId: data['projectId'] as String? ?? '',
      type: parseType(data['type'] as String? ?? 'other'),
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      affectedMaterials: List<String>.from(data['affectedMaterials'] as List? ?? []),
      expectedDeliveryDate: (data['expectedDeliveryDate'] as Timestamp).toDate(),
      reportedDate: (data['reportedDate'] as Timestamp).toDate(),
      createdBy: data['createdBy'] as String? ?? '',
      createdByName: data['createdByName'] as String? ?? '',
      status: parseStatus(data['status'] as String? ?? 'pending_consensus'),
      votes: votesMap,
      requiredVoters: List<String>.from(data['requiredVoters'] as List? ?? []),
      consensusAt: data['consensusAt'] != null ? (data['consensusAt'] as Timestamp).toDate() : null,
      managerResponse: data['managerResponse'] != null
          ? ManagerResponse.fromMap(data['managerResponse'] as Map<String, dynamic>)
          : null,
    );
  }

  // Computed helpers
  int get agreeCount => votes.values.where((v) => v.vote == VoteChoice.agree).length;
  int get disagreeCount => votes.values.where((v) => v.vote == VoteChoice.disagree).length;
  int get totalVoters => requiredVoters.length + 1; // +1 for creator
  int get votedCount => votes.length;
  bool get allVoted => votes.length >= totalVoters;
  bool get majorityAgree => agreeCount > (totalVoters / 2);

  bool hasVoted(String uid) => votes.containsKey(uid);
  VoteChoice? myVote(String uid) => votes[uid]?.vote;

  String get statusLabel => switch (status) {
    DelayNoticeStatus.pendingConsensus        => 'Awaiting Team Vote',
    DelayNoticeStatus.approved                => 'Pending Manager Review',
    DelayNoticeStatus.rejectedByTeam          => 'Rejected by Team',
    DelayNoticeStatus.acknowledgedExtended    => 'Extension Granted',
    DelayNoticeStatus.acknowledgedNoExtension => 'Acknowledged — No Extension',
    DelayNoticeStatus.rejectedByManager       => 'Rejected by Manager',
  };
}
