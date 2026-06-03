//
//  main.swift
//  CameraExtension
//
//  Created by Logan Rupe on 20/5/2026.
//

import Foundation
import CoreMediaIO

let providerSource = CameraExtensionProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
