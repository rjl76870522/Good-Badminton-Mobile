import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'offline_report_storage.dart';

class OfflineSaveState {
  const OfflineSaveState({
    this.taskId,
    this.videoName = '',
    this.progress = 0,
    this.stage = '',
    this.running = false,
    this.completedRecord,
    this.error,
    this.revision = 0,
  });

  final String? taskId;
  final String videoName;
  final double progress;
  final String stage;
  final bool running;
  final OfflineReportRecord? completedRecord;
  final Object? error;
  final int revision;
}

class OfflineSaveCoordinator extends ChangeNotifier {
  OfflineSaveCoordinator._();

  static final OfflineSaveCoordinator instance = OfflineSaveCoordinator._();

  final ApiService _api = ApiService();
  final OfflineReportStorage _storage = OfflineReportStorage();
  OfflineSaveState _state = const OfflineSaveState();
  Future<OfflineReportRecord>? _activeSave;

  OfflineSaveState get state => _state;

  Future<OfflineReportRecord> save({
    required String taskId,
    required String videoName,
  }) {
    final active = _activeSave;
    if (active != null) {
      if (_state.taskId == taskId) return active;
      throw StateError('已有一条训练记录正在保存，请等待完成');
    }

    _state = OfflineSaveState(
      taskId: taskId,
      videoName: videoName,
      stage: '准备保存',
      running: true,
      revision: _state.revision + 1,
    );
    notifyListeners();
    final future = _runSave(taskId: taskId, videoName: videoName);
    _activeSave = future;
    return future;
  }

  Future<OfflineReportRecord> _runSave({
    required String taskId,
    required String videoName,
  }) async {
    try {
      final record = await _storage.save(
        api: _api,
        taskId: taskId,
        videoName: videoName,
        onProgress: (progress, stage) {
          _state = OfflineSaveState(
            taskId: taskId,
            videoName: videoName,
            progress: progress,
            stage: stage,
            running: true,
            revision: _state.revision,
          );
          notifyListeners();
        },
      );
      _state = OfflineSaveState(
        taskId: taskId,
        videoName: videoName,
        progress: 1,
        stage: '离线保存完成',
        completedRecord: record,
        revision: _state.revision + 1,
      );
      notifyListeners();
      return record;
    } catch (error) {
      _state = OfflineSaveState(
        taskId: taskId,
        videoName: videoName,
        stage: '离线保存失败',
        error: error,
        revision: _state.revision + 1,
      );
      notifyListeners();
      rethrow;
    } finally {
      _activeSave = null;
    }
  }
}
