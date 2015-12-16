# React Native FileTransfer (remobile)
A file-transfer for react-native, code come from cordova, support for android and ios

## Installation
```sh
npm install @remobile/react-native-file-transfer --save
```

### Installation (iOS)
* Drag RCTFileTransfer.xcodeproj to your project on Xcode.
* Click on your main project file (the one that represents the .xcodeproj) select Build Phases and drag libRCTFileTransfer.a from the Products folder inside the RCTFileTransfer.xcodeproj.
* Look for Header Search Paths and make sure it contains $(SRCROOT)/../../../react-native/React as recursive.

### Installation (Android)
```gradle
...
include ':react-native-file-transfer'
project(':react-native-file-transfer').projectDir = new File(rootProject.projectDir, '../node_modules/@remobile/react-native-file-transfer/android')
```

* In `android/app/build.gradle`

```gradle
...
dependencies {
    ...
    compile project(':react-native-file-transfer')
}
```

* register module (in MainActivity.java)

```java
import com.remobile.filetransfer.*;  // <--- import

public class MainActivity extends Activity implements DefaultHardwareBackBtnHandler {
  ......
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    mReactRootView = new ReactRootView(this);

    mReactInstanceManager = ReactInstanceManager.builder()
      .setApplication(getApplication())
      .setBundleAssetName("index.android.bundle")
      .setJSMainModuleName("index.android")
      .addPackage(new MainReactPackage())
      .addPackage(new RCTFileTransferPackage())              // <------ add here
      .setUseDeveloperSupport(BuildConfig.DEBUG)
      .setInitialLifecycleState(LifecycleState.RESUMED)
      .build();

    mReactRootView.startReactApplication(mReactInstanceManager, "ExampleRN", null);

    setContentView(mReactRootView);
  }

  ......
}
```

## Usage

### Example
```js
var React = require('react-native');
var {
    StyleSheet,
    NativeAppEventEmitter,
    View,
    Text,
} = React;

var FileTransfer = require('@remobile/react-native-file-transfer');
var Button = require('@remobile/react-native-simple-button');

module.exports = React.createClass({
    testUpload() {
        var fileURL = app.isandroid?'file:///sdcard/data/1.jpg':'file:///Users/fang/node/test/post.js';
        var options = {};
        options.fileKey = 'file';
        options.fileName = fileURL.substr(fileURL.lastIndexOf('/')+1);
        options.mimeType = 'text/plain';

        var params = {};
        params.value1 = 'test';
        params.value2 = 'param';

        options.params = params;
        var fileTransfer = new FileTransfer();
        fileTransfer.onprogress = (progress) => console.log(progress);


        fileTransfer.upload(fileURL, encodeURI('http://192.168.1.119:3000/upload'),(result)=>{
            console.log(result);
        }, (error)=>{
            console.log(error);
        }, options);
    },
    testDownload() {
        var fileTransfer = new FileTransfer();
          var uri = encodeURI("http://192.168.1.119:3000/Framework7.zip");
          fileTransfer.onprogress = (progress) => console.log("1",progress.loaded+'/'+progress.total);
          fileTransfer.download(
              uri,
              app.isandroid?'/sdcard/data/xx.html':'/Users/fang/oldwork/client/server/xx.zip',
              function(result) {
                  console.log(result);
              },
              function(error) {
                  console.log(error);
              },
              true
          );
    },
    render() {
        return (
            <View style={styles.container}>
                <Button onPress={this.testUpload}>
                    Test Upload
                </Button>
                <Button onPress={this.testDownload}>
                    Test Download
                </Button>
            </View>
        );
    },
});


var styles = StyleSheet.create({
    container: {
        flex: 1,
        justifyContent: 'space-around',
        alignItems: 'center',
        backgroundColor: 'transparent',
        paddingVertical:200,
    }
});
```

### HELP
* look https://github.com/apache/cordova-plugin-file-transfer


### thanks
* this project come from https://github.com/apache/cordova-plugin-file-transfer
