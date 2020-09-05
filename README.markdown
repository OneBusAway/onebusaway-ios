# OBAKit

OBAKit is a rewrite of OneBusAway for iOS from the ground up. The codebase is explicitly designed to be easy to understand, test, and maintain. This is the foundation of OneBusAway's second decade of life on Apple platforms.

## Quick Start

To get started, you will need the following pieces of software installed on your computer:

1. [Xcode 11.x](https://apps.apple.com/us/app/xcode/id497799835) - Once installed, please launch Xcode and install any ancillary pieces of software about which it may prompt you.
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
    scripts/carthage_build
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

## Internationalization and Localization

_Note: There's a lot more to be written on this topic. Don't hesitate to ask questions if something is wrong or confusing._

We are using [Twine](https://github.com/scelis/twine) to manage localization. See the `Translations` folder for the three files that need to be updated in order to localize the app: `InfoPlist.txt`, `OBAKit.txt` and `OBAKitCore.txt`.

### How to Add a New Localizable String

If you need to add a new string to one of the frameworks, please do the following:

1. Use the function `OBALoc` instead of `NSLocalizedString`. Search the codebase for examples of the syntax and include a useful comment.
2. Run the script `scripts/extract_strings` from the Terminal. (note: it will respond with some warnings; these are normal and can be ignored.)
3. Clean up the new 'uncategorized' string table entries that have been added to the Twine localization files (make sure they get alphabetized, and the 'uncategorized' header is removed.)
4. Run the script `scripts/localize` to reduce the amount of churn in the Localizable.strings files, and to make sure temporary placeholder strings are generated for the languages supported by the app.
5. Open an issue documenting the need for new localized strings, including links to file lines that show which strings need to be translated.

### How to Translate a String in the App

Currently, the app is configured to work in English and Polish. To translate a string in a supported language that is currently not localized, for example, into Polish:

1. Open `Translations/OBAKitCore.txt` and `Translations/OBAKit.txt`.
2. Add translations for the strings on lines beginning with `pl = `
3. To test your changes, run the command `scripts/localize` from the command line and then launch the app (note: make sure the iOS Simulator is set to your desired language.)

Read on for how to add a new language or dialect.

### How to Add a New Language or Dialect

To translate the app into another language or dialect, you will first need to find the Language ID for your desired localization target. Start by reading through Apple's [documentation on Language IDs](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPInternational/LanguageandLocaleIDs/LanguageandLocaleIDs.html#//apple_ref/doc/uid/10000171i-CH15), and determine if you need to choose just a language designator, or a language designator plus a region designator.

For example, if you wanted to add Standard German to the app, you would specify the Language ID `de`, or to add Argentinian Spanish, you would specify the Language ID `es-AR`.

Once you know the Language ID that you will need to use, you must open the `Translations` directory in the root of the project. Each `.txt` file contained in there contains many string entries that need to be translated into your desired Language ID. For instance, here's the entry for the English verb "Close":

    [common.close]
        en = Close
        comment = The verb 'to close'.
        pl = Zamknij

To translate `common.close` into a new language, add a new line below `pl`:

    [common.close]
        en = Close
        comment = The verb 'to close'.
        pl = Zamknij
        de = Schließen

To test your changes, run the command `scripts/localize` from the command line and then launch the app (note: make sure the iOS Simulator is set to your desired language.)

## Diagnosing Problems

### Command Line Errors?

If the `xcode-select --install` command results in an error message that the command line tools are already installed, you can verify that you have the latest version by typing the command `softwareupdate --list` to check whether any software should be updated; then if need be use `softwareupdate --install <project>` to  update it.

If the `carthage build --platform iOS` command gives an error claiming that it is unable to find utility "xcodebuild" because it is not a developer tool or in PATH, this should fix it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Or see this github issue for other potential solutions: https://github.com/nodejs/node-gyp/issues/569

### Swift Compiler Errors?

If you see errors that look like this when you compile:

```bash
error: module compiled with Swift 4.0 cannot be imported in Swift 4.0.3: /onebusaway/OBAKit/../Carthage/Build/iOS/PromiseKit.framework/Modules/PromiseKit.swiftmodule/x86_64.swiftmodule
```

this is happening because the project's Carthage frameworks were compiled with an older version of the Swift compiler than the one you have on your computer. To fix, recompile the Carthage dependencies with this command from the command line:

```bash
carthage build --platform iOS --no-use-binaries
```

After Carthage finishes, we recommend cleaning your project and possibly deleting all of your build artifacts.

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

## Frameworks

The app is essentially a thin shell around two frameworks, `OBAKitCore` and `OBAKit`. `OBAKitCore` is responsible for networking, data models and storage, location services, and region management. `OBAKit` provides an iOS-compatible user interface that can easily be created from an app that consumes `OBAKit`.

## Functional Areas

### Protobuf

To make modifications to the local copy of `gtfs-realtime.proto`, you will need to install some new tools via the `brew` command:

```bash
brew install protobuf
brew install swift-protobuf
```

Now, replace the file `OBAKitCore/Models/Protobuf/gtfs-realtime.proto` with the updated version, and run `scripts/proto-gen.sh` from the project root.

You can find the latest version of the GTFS-RT protobuf file in the https://github.com/google/transit/ repository.

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

## SVProgressHUD

<details>
    <summary>Includes SVProgressHUD by Sam Vermette, Tobias Tiemerding and contributors.</summary>
    
    ```
    v2.2.6, plus Dark Mode support.
    
    MIT License

    Copyright (c) 2011-2018 Sam Vermette, Tobias Tiemerding and contributors.

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
