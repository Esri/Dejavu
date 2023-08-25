## Configuring a location to store mocked data

You'll need to configure a location to store the data that Dejavu will record and playback. For example, the included `Examples` project uses `/ExamplesTests/MockedData`.

Once you've identified a location open the `Info` tab of your project's main target and add a key that can be programatically referenced (e.g. [here](https://github.com/ArcGIS/Dejavu/blob/a805c38bdba9f160676e283525c734ad31808f47/Examples/ExamplesTests/Test%20Support/Extensions/Foundation/URL%2BTestData.swift#L21)).

<picture>
    <source media="(prefers-color-scheme: dark)" srcset="./Resources/Info_Key_Dark.png">
    <source media="(prefers-color-scheme: light)" srcset="./Resources/Info_Key_Light.png">
    <img alt="An image of a  target's Info.plist seetings pane.">
</picture>