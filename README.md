# InfiniteRide Ultimate for iOS

Native iPhone/iPad cycling computer and race companion by **INfiniteBoost45**. This is not an Android wrapper: the iOS edition uses SwiftUI, CoreBluetooth, CoreLocation and MapKit.

## Included in the iOS 1.0 build

- Preview-inspired OLED Home, Ride, Data, Coach and Profile interface in portrait and landscape.
- Start choices for Solo Ride, Solo Time Trial, Criterium, Team Time Trial and Team Road Race.
- Simultaneous BLE selection and connection for standard Heart Rate, Cycling Speed/Cadence and Cycling Power sensors.
- GPS speed/location fallback and physics-modeled power when no power meter is live.
- One-second ride capture, pause/resume, lap marker, Finish + Save and Discard Activity.
- 3D/pitched Apple Map route view with a course-direction arrow.
- FIT, GPX, TCX and InfiniteRide CSV import; every import is saved, analyzed and available as a race route.
- CSV and GPX export through the iOS share sheet.
- Conservative cycling VO₂, FTP, sustained-speed and five-second sprint estimates.
- Separate VO₂/Test and Short Range fitness sections.
- App-to-app Bluetooth rider scan, Friend/Teammate links, editable names and race roles.
- Live race rider position, team spread, distance remaining and adjustable sprint alert.

## Build the unsigned Scarlet IPA

The included workflow uses an official macOS/Xcode runner, compiles an ARM64 iPhone application without an Apple signature, packages the required `Payload/InfiniteRide.app` structure, verifies the executable, and publishes `InfiniteRideUltimate-iOS-1.0-Scarlet.ipa` as a workflow artifact.

1. Create an empty private GitHub repository.
2. Upload the contents of this folder so `project.yml` and `.github` are at the repository root.
3. Open **Actions → Build Scarlet IPA → Run workflow**.
4. Download the `InfiniteRideUltimate-iOS-Scarlet` artifact when the green build finishes.
5. Extract the artifact ZIP, then give the `.ipa` file to Scarlet.

Scarlet supplies its own signature during installation. Certificate availability, revocation and device compatibility are controlled by the sideloading service, not InfiniteRide.

## Privacy and safety

Ride files and athlete settings remain on the phone unless explicitly shared. Nearby rider exchange only operates while enabled and does not send an email address or stored route history. VO₂ and FTP results are training estimates, not medical measurements. Do not interact with the phone while riding in traffic.
