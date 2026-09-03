/// Coordinates slip ingestion around Android picker lifecycle changes.
///
/// The resume caused by returning from a picker is deliberately not scanned.
/// The persistent automatic cursor is not advanced, so the next genuine
/// resume/cold start still discovers non-selected images created meanwhile.
final class SlipMediaLifecycleGate {
  bool _manualSelectionActive = false;
  bool _automaticScanDeferred = false;

  bool get manualSelectionActive => _manualSelectionActive;
  bool get automaticStagingAllowed => !_manualSelectionActive;
  bool get automaticScanDeferred => _automaticScanDeferred;

  void beginManualSelection() => _manualSelectionActive = true;

  void deferAutomaticScan() {
    if (_manualSelectionActive) _automaticScanDeferred = true;
  }

  void endManualSelection() {
    _manualSelectionActive = false;
    _automaticScanDeferred = false;
  }
}
