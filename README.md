# React Native FileTransfer (remobile)
A file-transfer for react-native, code come from cordova, support for android and ios

## Installation
```sh
npm install @remobile/react-native-file-transfer --save
```

### Installation (iOS)
* Drag RCTFileTransfer.xcodeproj to your project on Xcode.
* Click on your main project file (the one that represents the .xcodeproj) select Build Phases and drag libRCTFileTransfer.a from the Products folder inside the RCTFileTransfer.xcodeproj.
* Look for Header Search Paths and make sure it contains both $(SRCROOT)/../react-native/React as recursive.

### Installation (Android)
```gradle
...
include ':react-native-file-transfer'
project(':react-native-file-transfer').projectDir = new File(rootProject.projectDir, '../node_modules/react-native-file-transfer/android')
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

var FileTransfer = require('react-native-file-transfer');
var Button = require('@remobile/react-native-simple-button');

module.exports = React.createClass({
    getInitialState () {
        return {
            image:null,
        };
    },
    uploadSuccessCallback(ret) {
        console.log(ret);
        this.uploadProgress.remove();
    },
    uploadErrorCallback(error) {
        console.log(error);
        this.uploadProgress.remove();
    },
    testUpload() {
        var fileURL = 'file:///Users/fang/node/test/post.js';
        var options = new FileTransfer.FileUploadOptions();
        options.fileKey = 'file';
        options.fileName = fileURL.substr(fileURL.lastIndexOf('/')+1);
        options.mimeType = 'text/plain';

        var params = {};
        params.value1 = 'test';
        params.value2 = 'param';

        options.params = params;
        var ft = new FileTransfer();

        this.uploadProgress = NativeAppEventEmitter.addListener(
          'uploadProgress',
          (progress) => console.log(progress)
        );

        ft.upload(fileURL, encodeURI('http://192.168.1.117:3000/upload'), this.uploadSuccessCallback, this.uploadErrorCallback, options);
    },
    testDownload() {
        var fileTransfer = new FileTransfer();
          var uri = encodeURI("http://192.168.1.117:3000/helpAndAbout/help");
          this.downloadProgress = NativeAppEventEmitter.addListener(
            'downloadProgress',
            (progress) => console.log(progress)
          );
          var self = this;
          fileTransfer.download(
              uri,
            //   '/Users/fang/oldwork/client/server/xxx.html',
            '/sdcard1/1/xx.html',
              function(entry) {
                  console.log(entry);
                  self.downloadProgress.remove();
              },
              function(error) {
                  console.log(error);
                  self.downloadProgress.remove();
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
        paddingVertical:250,
    }
});
```

### HELP
* look https://github.com/apache/cordova-plugin-file-transfer


### thanks
* this project come from https://github.com/apache/cordova-plugin-file-transfer
