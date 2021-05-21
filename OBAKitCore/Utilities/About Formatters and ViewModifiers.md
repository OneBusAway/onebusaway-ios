# `Utilities/Formatters.swift` and `SwiftUI/ViewModifiers/`

- `Utilities/Formatters.swift`: UIKit formatters
- `SwiftUI/ViewModifiers/`: SwiftUI view modifiers

View modifiers may have duplicate behavior as `Formatters.swift`.

Basically, if you change something in `Formatters.swift`, you may need to also change 
something in `ViewModifiers` to reflect the change in both UIKit and SwiftUI.

At the time of writing, SwiftUI is sparingly used in OBAKit (primarily in Widget), so I won't
be writing any "glue" code between UIKit and SwiftUI to use one codebase. 

`ViewModifiers` is written in a way that is easier to preview (and debug) and is a first-class 
SwiftUI paradigm. This could be changed in the future depending on how we adopt SwiftUI 
into the main app.
