# ARIS – Augmented Reality Integrated System

ARIS (Augmented Reality Integrated System) is a wearable smart glasses prototype designed to provide real-time information through an OLED display while communicating wirelessly with an iOS application.

This project combines embedded systems, mobile development, Bluetooth Low Energy (BLE), and user interface design to create a functional augmented reality platform.

## Features

- Bluetooth Low Energy (BLE) communication between ESP32 and iOS app
- OLED display output for wearable smart glasses
- SwiftUI-based iOS companion application
- Real-time data transmission and display
- Location and mapping integration
- Custom navigation and user interface system
- Embedded firmware development using ESP32

## Technologies Used

### Embedded Systems
- ESP32
- C/C++
- Arduino IDE
- OLED Display
- Bluetooth Low Energy (BLE)

### Mobile Application
- Swift
- SwiftUI
- CoreBluetooth
- CoreLocation
- MapKit

## System Architecture
iOS Application (SwiftUI)
           │
           │ BLE
           ▼
ESP32 Microcontroller
           │
           ▼
OLED Display
