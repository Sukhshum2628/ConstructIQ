class UnassignedCompanyException implements Exception {
  final String message;
  const UnassignedCompanyException([this.message = 'User has no company assigned']);

  @override
  String toString() => message;
}
