# Weather map button

The map weather control shows a condition SF Symbol plus the temperature
(for example a sun icon above `71°`). The full condition word is not used as
the visible title because it will not fit the 42pt hover bar.

VoiceOver still gets both pieces: the button's accessibility label stays
"Show Weather Forecast", and the value is temperature plus condition
(`71°, Clear`). An unknown icon still speaks the temperature, with `—` for
the condition.

Hour-by-hour forecast is the existing weather popup (`WeatherDetailPopup`),
not this control.
