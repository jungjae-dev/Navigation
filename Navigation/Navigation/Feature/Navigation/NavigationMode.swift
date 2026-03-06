enum NavigationMode {
    case realNavigation
    case virtualDrive(engine: VirtualDriveEngine)
    case gpxPlayback(simulator: GPXSimulator)
}
