# OBAKit

<img src="WebResources/OBAKit-Logo-Web.png" alt="OBAKit">

OBAKit is a total rewrite of OneBusAway for iOS in the Swift programming language.

## Purpose and Goals

* This codebase is built as a set of reusable frameworks, which can be used to make new apps or augment existing apps on a wide variety of platforms.
* This codebase is meant to provide an easy way for transit agencies to create their own custom-branded transit apps without needing to fork the OneBusAway source code.
* This codebase is intended to be easy to understand, test, and maintain. We try to emphasize clarity over cleverness, even at the risk of being somewhat more verbose at times.
## Quick Start

To get started, you will need the following pieces of software installed on your computer:

1. [Xcode 12.x](https://apps.apple.com/us/app/xcode/id497799835) - Once installed, please launch Xcode and install any ancillary pieces of software about which it may prompt you.
1. [Homebrew](https://brew.sh) - A package manager used to install Xcodegen.
1. [XcodeGen](https://github.com/yonaskolb/XcodeGen) - This is used to generate the `xcodeproj` file used to build the project.
1. [SwiftLint](https://github.com/realm/SwiftLint) - A tool to enforce Swift style and conventions.
1. [Ruby](https://www.ruby-lang.org/) - _This should already be installed on your Mac_. A dynamic, open source programming language with a focus on simplicity and productivity.
1. [RVM](https://rvm.io) - _Optional, but very helpful_. RVM is a command-line tool which allows you to easily install, manage, and work with multiple Ruby environments from interpreters to sets of gems.

Once you have these pieces of software installed, clone the OneBusAway app repository on GitHub. (After this rewrite becomes the official version of the app, it will be in the OneBusAway GitHub repository; for now ask Aaron for an invitation.)

    # Make sure you have Xcode 12.x and Homebrew installed.
    xcode-select --install
    brew install xcodegen
    brew install swiftlint
    # open the directory with the app code
    cd OBAKit
    # note: depending on your system configuration, you may need to run this command with sudo, i.e. sudo gem install bundler
    gem install bundler
    bundle install
    scripts/generate_project OneBusAway
    open OBAKit.xcodeproj

## Project Files (.xcodeproj)

The directions above include a command `scripts/generate_project OneBusAway` to create the `xcodeproj` project file.  If you just want to build the OneBusAway app, that's all you need.  Here is some additional information in case you want to generate a different app.

OBAKit uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to create the `xcodeproj` file that makes Xcode function. XcodeGen takes a simple YAML file (`project.yml`) and turns it into a full-fledged `xcodeproj`. This makes it much easier to support white-labeling and managing multiple project targets.

Call `scripts/generate_project` from the project root directory with the name of a directory in `Apps`. So to generate the OneBusAway app, you run the command:

```bash
scripts/generate_project OneBusAway
```

Run `scripts/generate_project` on its own to see a list of available app targets.

## White Label Support

To create your own app target, duplicate the `Apps/OneBusAway` directory and update all of the available variables with the ones that are relevant to your project. [Learn more about White Label support by reading the documentation on the subject](Tutorials/WhiteLabel.md).

## Sub-Projects

The app, whether it is OneBusAway, KiedyBus, YRTViva, or another, is just a thin shell on top of two frameworks: `OBAKitCore` and `OBAKit`.

`OBAKitCore` is responsible for networking, data models and storage, location services, and region management.

`OBAKit` provides an iOS-compatible user interface that can easily be created from any app that consumes `OBAKit`.

`TodayView`, if your project supports it, is a widget that provides the user with easy access to a subset of their bookmarked transit routes from the [Today View](https://support.apple.com/guide/iphone/add-widgets-iphb8f1bf206/ios).

## Internationalization and Localization

_Note: There's a lot more to be written on this topic. Don't hesitate to ask questions if something is wrong or confusing._

We are using Transifex to localize OneBusAway. You can help out by visiting [the OBA page on Transifex](https://www.transifex.com/open-transit-software-foundation/onebusaway-ios/).

Install the Transifex command line client (`tx`) by following the instructions here: https://docs.transifex.com/client/installing-the-client

For help configuring your Python environment on macOS, look here: https://opensource.com/article/19/5/python-3-default-mac

Use `tx` by following the instructions here: https://docs.transifex.com/client/introduction

Get an API token to use with `tx` by following the instructions here: https://docs.transifex.com/account/authentication

Fetch updated strings from Transifex by running the command `scripts/tx_pull`.

`tx_pull` extracts the full list of localizations that are specified in `app_shared.yml`, and requests the latest list of strings for each language from Transifex by calling `tx pull -l {LANG CODE}` under the hood.

## Objective-C Compatibility

OBAKit is written almost entirely in Swift, with the exception of a few small, ancillary pieces of code. This project is designed to be usable within both Swift and Objective-C projects. Please open an issue for scenarios encountered where you are unable to effectively use the framework generated by this project in Objective-C code.

## Documentation

This project uses [Jazzy](https://github.com/realm/jazzy/) and [Sourcekitten](https://github.com/jpsim/SourceKitten) to generate its documentation. To rebuild documentation, you will first need to have both projects installed:

```bash
bundle install
brew install sourcekitten
```

Once you have the necessary tools installed, you can regenerate documentation by running the command:

```bash
scripts/docs
```

Configuration data for the Jazzy-generated documentation can be found in the file `.jazzy.json` in the root of the repository.

## How-To's

### Protobuf

To make modifications to the local copy of `gtfs-realtime.proto`, you will need to install some new tools via the `brew` command:

```bash
brew install protobuf
brew install swift-protobuf
```

Now, replace the file `OBAKitCore/Models/Protobuf/gtfs-realtime.proto` with the updated version, and run `scripts/proto-gen.sh` from the project root.

You can find the latest version of the GTFS-RT protobuf file in the https://github.com/google/transit/ repository.

# App Store Graphics

[The App Store page for OneBusAway](https://apps.apple.com/us/app/onebusaway/id329380089) uses the [Hotpot.ai](https://hotpot.ai) to generate its nifty panoramic screenshots.

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

## SwipeCellKit

Version 2.7.1 / https://github.com/SwipeCellKit/SwipeCellKit/commit/6d632bdf1b7309505566b0248a00f61b67415a37

<details>
  <summary>Includes SwipeCellKit by Jeremy Koch, Mo Kurabi, and contributors</summary>
  ```
  MIT License
  Copyright (c) 2017 Jeremy Koch

  http://jerkoch.com

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

## ProgressHUD

<details>
    <summary>Includes ProgressHUD by Related Code.</summary>

    ```
    v13.4

    MIT License

    Copyright (c) 2020 Related Code.

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

    Copyright 2018-Present Open Transit Software Foundation

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
