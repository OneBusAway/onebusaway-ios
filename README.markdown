# OBAKit

This library is a ground-up rewrite of the core modules of OneBusAway for iOS. It is designed to be stable, relatively bug-free, clear, and well-tested. It is designed to serve as the foundation of OneBusAway for iOS in its second decade of life.

## Quick Start

To get started, you will need the following pieces of software installed on your computer:

1. [Xcode 11.x](https://apps.apple.com/us/app/xcode/id497799835) - Once installed, please launch Xcode and install any ancillary pieces of software it may prompt you to install.
2. [Homebrew](https://brew.sh) - A package manager used to install Xcodegen and Carthage.
3. [XcodeGen](https://github.com/yonaskolb/XcodeGen) - This is used to generate the `xcodeproj` file used to build the project.
4. [Carthage](https://github.com/Carthage/Carthage) - Manages third-party dependencies.
5. [SwiftLint](https://github.com/realm/SwiftLint) - A tool to enforce Swift style and conventions.
6. [Ruby](https://www.ruby-lang.org/) - _This should already be installed on your Mac_. A dynamic, open source programming language with a focus on simplicity and productivity.
7. [RVM](https://rvm.io) - _Optional, but very helpful_. RVM is a command-line tool which allows you to easily install, manage, and work with multiple Ruby environments from interpreters to sets of gems.

Once you have these pieces of software installed, clone the OneBusAway app repository on GitHub. (After this rewrite becomes the official version of the app, it will be in the OneBusAway GitHub repository; for now ask Aaron for an invitation.)

    # Make sure you have Xcode 11.x and Homebrew installed.
    xcode-select --install
    brew install xcodegen
    brew install carthage
    brew install swiftlint
    # open the directory with the app code
    cd OBAKit
    # note: depending on your system configuration, you may need to run this command with sudo, i.e. sudo gem install bundler
    gem install bundler
    bundle install
    carthage build --platform iOS
    scripts/generate_project
    open OBAKit.xcodeproj

## Project Files

tl;dr: run `scripts/generate_project` to create the `xcodeproj` project file.

OBAKit uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to create the `xcodeproj` file that you open in Xcode. XcodeGen takes a simple YAML file (`project.yml`) and turns it into a full-fledged `xcodeproj`. This makes it much easier to support whitelabeling and managing multiple project targets.

However, YAML does not support variables, which we need, so we actually generate the `project.yml` file that is fed to `xcodegen` via a Ruby script, `scripts/generate_project`. `scripts/generate_project` injects the variables in `Apps/Shared/variables.yml` into a 'template' version of the `project.yml` file, which is located at `Apps/Shared/project.yml.erb`, outputs the resulting YAML file to `project.yml`, and then invokes `xcodegen`.

## Internationalization and Localization

_Note: There's a lot more to be written on this topic. Don't hesitate to ask questions if something is wrong or confusing._

We are using [Twine](https://github.com/scelis/twine) to manage localization. See the `Translations` folder for the two files that need to be updated in order to localize the app: `OBAKit.txt` and `OBAKitCore.txt`.

### How to Translate the App

Currently, the app is configured to work in English and Polish.

To translate a string for example into Polish:

1. Open `Translations/OBAKitCore.txt` and `Translations/OBAKit.txt`.
2. Add translations for the strings on lines beginning with `pl = `
3. To test your changes, run the command `scripts/localize` from the command line and then launch the app (note: make sure the iOS Simulator is set to your desired language.)

### How to Add a New Localizable String

If you need to add a new string to one of the frameworks, please do the following:

1. Use the function `OBALoc` instead of `NSLocalizedString`. Search the codebase for examples of the syntax and include a useful comment.
2. Add a new definition for the string to either `Translations/OBAKitCore.txt` or `Translations/OBAKit.txt`, depending on which framework you are working in, and include the key, default English value, and comment that you added to the code. (_AB/January 2, 2020: I'm trying to figure out how to make this process easier_)
3. Generate the new `.strings` file.

To generate new `.strings` files, run this command from the root of the project:

    scripts/localize
    
## Diagnosing Problems

### Command Line Errors?

If the `xcode-select --install` command results in an error message that the command line tools are already installed, you can verify that you have the latest version by typing the command `softwareupdate --list` to check whether any software should be updated; then if need be use `softwareupdate --install <project>` to  update it.

If the `carthage build --platform iOS` command gives an error claiming that it is unable to find utility "xcodebuild" because it is not a developer tool or in PATH, this should fix it:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
Or see this github issue for other potential solutions: https://github.com/nodejs/node-gyp/issues/569

## Code and Structure

OBAKit is written almost entirely in Swift, with the exception of a few small, ancillary pieces of code.

### Objective-C Compatibility

This project is designed to be usable within both Swift and Objective-C projects. Please open an issue for scenarios encountered where you are unable to effectively use the framework generated by this project in Objective-C code.

## Documentation

This project uses [Jazzy](https://github.com/realm/jazzy), which is written in Ruby, to generate its documentation. To install Jazzy, we recommend following these steps:

```
gem install bundler
bundle install
```

Once Jazzy is installed, you can generate the project's documentation by running the command

```
jazzy
```

### Documentation Bugs

Please log bugs with the label `Documentation` on any issues with the documentation, either because the documentation is missing or misleading.

## Frameworks

The app is essentially a thin shell around two frameworks, `OBAKitCore` and `OBAKit`. `OBAKitCore` is responsible for networking, data models and storage, location services, and region management. `OBAKit` provides an iOS-compatible user interface that can easily be created from an app that consumes `OBAKit`. 

## Functional Areas

### Protobuf

To make modifications to the local copy of `gtfs-realtime.proto`, you will need to install some new tools via the `brew` command:

```
brew install protobuf
brew install swift-protobuf
```

Now, `cd OBAKitCore/Models/Protobuf`, replace the `gtfs-realtime.proto` file with the modified version, and run `./proto-gen.sh`.

### Networking

`OBAKitCore` includes a network service layer and a model service layer, each of which have three service classes designed to work with the three data sources that OneBusAway for iOS depends on:

* Regions API
* REST API
* Obaco API (alerts.onebusaway.org or onebusaway.co)

This library would be suitable for using on its own in a custom application that would only need to communicate with a single, previously-defined OneBusAway server.

### Location

Region and location management helps to determine where the user is located in the world, and which OBA region, if any, they are currently located in.

### User Data Services

Management of bookmarks, recently-viewed stops, and other similar data. Basically, any data generated directly or indirectly by the user. This layer is designed around the `UserDataStore` protocol, which should lend itself to being used across multiple implementations. For now, the only implementation provided uses `NSUserDefaults`, but CloudKit or Firebase support, e.g., should be relatively easy to implement.

### OBAKit

This is comprised of view controllers (e.g. `RecentStopsViewController`), controls (e.g. `BorderedButton`), theme support &amp; icons, and orchestration. 'Orchestration' is a catch-all name for the layer of the software that you, the developer, give a set of configuration data to, and are handed back a fully-configured `Application` object that represents a OneBusAway-style app. `Application` handles creating all of the services you'll need: REST, notifications, user data storage, and so forth.

# Third Party Libraries

These are third party libraries directly included inside of this project.

## AwesomeSpotlight

<details>
    <summary>Includes AwesomeSpotlight by Aleksandr Shoshiashvili.</summary>

    ```
    Copyright (c) 2017 aleksandrshoshiashvili aleksandr.shoshiashvili@gmail.com

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
    ```
</details>

## DictionaryCoding

<details>
  <summary>Includes DictionaryCoding code by Sam Deane, Elegant Chaos Limited.</summary>

  ```
  The original code is copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors

  Licensed under Apache License v2.0 with Runtime Library Exception

  See https://swift.org/LICENSE.txt for license information
  See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

  Modifications and additional code here is copyright (c) 2018 Sam Deane, and is licensed under the same terms.
  ```
</details>

## Polyline

<details>
    <summary>Includes Polyline.swift by Raphaël Mor.</summary>

    ```
    The MIT License (MIT)

    Copyright (c) 2015 Raphaël Mor

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    ```
</details>

## SVPulsingAnnotationView

<details>
    <summary>Copyright (c) 2013, Sam Vermette (hello@samvermette.com)</summary>

    ```
    Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby
    granted, provided that the above copyright notice and this permission notice appear in all copies.

    THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING
    ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL,
    DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
    PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION
    WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
    ```
</details>

## Visual Effects Shadow

<details>
    <summary>Includes Visual Effects Shadow by Brian Coyner.</summary>

    ```
    https://github.com/briancoyner/Visual-Effects-Shadow

    MIT License

    Copyright (c) 2017 Brian Coyner

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    ```
</details>

# Apache 2.0 License

All other code is made available under the Apache 2.0 license.

    Copyright 2018-Present Aaron Brethorst

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
