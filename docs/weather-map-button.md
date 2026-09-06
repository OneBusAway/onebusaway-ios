# Weather map button

The map weather control shows a condition SF Symbol plus the temperature.
The two surfaces stack it differently: the UIKit hover-bar button
(`MapViewController.weatherButton`) sets `imagePlacement = .top`, so the icon
sits *above* `71°`, while the SwiftUI pill (`WeatherButton`) lays them out in
an `HStack`, so the icon sits *beside* it. The full condition word is not used
as the visible title on either because it will not fit the 42pt hover bar.

VoiceOver still gets both pieces: the button's accessibility label stays
"Show Weather Forecast", and the value is temperature plus condition
(`71°, Clear`). An unknown icon still speaks the temperature, with `—` for
the condition.

Hour-by-hour forecast is the existing weather popup (`WeatherDetailPopup`),
not this control.
