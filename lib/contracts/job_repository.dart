import 'package:flutter/foundation.dart';

import 'job_feed.dart';

class JobFeedState {
  final JobFeed? feed;
  final bool isLoading;
  final bool isOffline;
  final String? lastError;
  const JobFeedState({
    this.feed,
    this.isLoading = false,
    this.isOffline = false,
    this.lastError,
  });
}

abstract class JobRepository {
  ValueListenable<JobFeedState> get state;
  Future<void> refresh();
  Future<void> dispose();
}
