Running "expo doctor"
npm WARN EBADENGINE Unsupported engine {
npm WARN
EBADENGINE   package: 'expo-doctor@1.18.21',
npm WARN EBADENGINE   required: { node: '^20.19.4 || ^22.13.0 || ^24.3.0 || >= 25.0.0' },
npm WARN EBADENGINE   current: { node: 'v20.11.1', npm: '10.2.4' }
npm WARN EBADENGINE }
Node.js (v20.11.1) is outdated and unsupported. Please update to a newer Node.js LTS version (required: >=20.19.4)
Go to: 
Running 17 checks on your project...
15/17 checks passed. 2 checks failed. Possible issues detected:
Use the --verbose flag to see more details about passed checks.

✖ Check that no duplicate dependencies are installed
Your project contains duplicate native module dependencies, which should be de-duplicated.
Native builds may only contain one version of any given native module, and having multiple versions of a single Native module installed may lead to unexpected build errors.
Found duplicates for @expo/vector-icons:
  ├─ @expo/vector-icons@14.0.2 (at: node_modules/@expo/vector-icons)
  └─ @expo/vector-icons@15.1.1 (at: node_modules/expo/node_modules/@expo/vector-icons)
Found duplicates for expo-font:
  ├─ expo-font@12.0.10 (at: node_modules/expo-font)
  └─ expo-font@14.0.11 (at: node_modules/expo/node_modules/expo-font)
Advice:
Resolve your dependency issues and deduplicate your dependencies. Learn more: 

✖ Check that packages match versions required by installed Expo SDK

❗ Major version mismatches
package                                    expected  found    
@expo/vector-icons                         ^15.0.3   14.0.2   
@react-native-async-storage/async-storage  2.2.0     1.23.1   
expo-build-properties                      ~1.0.10   0.12.5   
expo-document-picker                       ~14.0.8   12.0.2   
expo-font                                  ~14.0.11  12.0.10  
expo-linear-gradient                       ~15.0.8   13.0.2   
expo-local-authentication                  ~17.0.8   14.0.1   
expo-status-bar                            ~3.0.9    1.12.1   
react                                      19.1.0    18.2.0   
react-dom                                  19.1.0    18.2.0   
react-native-reanimated                    ~4.1.1    3.10.1   
react-native-safe-area-context             ~5.6.0    4.10.5   
react-native-screens                       ~4.16.0   3.31.1   
@types/react                               ~19.1.10  18.2.79  

⚠️ Minor version mismatches
package                                    expected  found    
react-native                               0.81.5    0.74.5   
react-native-gesture-handler               ~2.28.0   2.16.2   
react-native-web                           ^0.21.0   0.19.13  
react-native-webview                       13.15.0   13.8.6   
@babel/core                                ^7.26.0   7.24.8   
typescript                                 ~5.9.2    5.3.3    

🔧 Patch version mismatches
package                                    expected  found    
expo                                       ~54.0.34  54.0.13  

Changelogs:
- expo-build-properties → 
- expo-document-picker → 
- expo-font → 
- expo-linear-gradient → 
- expo-local-authentication → 
- expo-status-bar → 

21 packages out of date.
Advice:
Use 'npx expo install --check' to review and upgrade your dependencies.
To ignore specific packages, add them to "expo.install.exclude" in package.json. Learn more: 
2 checks failed, indicating possible issues with the project.
Command "expo doctor" failed.

Running 'gradlew :app:bundleRelease' in /home/expo/workingdir/build/android
Downloading 
10%
20%.
30%.
40%.
50%.
60%.
70%.
80%.
90%.
100%
Welcome to Gradle 8.14.3!
Here are the highlights of this release:
 - Java 24 support
- GraalVM Native Image toolchain selection
 - Enhancements to test reporting
 - Build Authoring improvements
For more details see 
To honour the JVM settings for this build a single-use Daemon process will be forked. For more on this, please refer to  in the Gradle documentation.
Daemon will be stopped at the end of the build
> Configure project :gradle-plugin:react-native-gradle-plugin
e: file:///home/expo/workingdir/build/node_modules/@react-native/gradle-plugin/react-native-gradle-plugin/build.gradle.kts:10:49: Unresolved reference: serviceOf
e: file:///home/expo/workingdir/build/node_modules/@react-native/gradle-plugin/react-native-gradle-plugin/build.gradle.kts:54:11: Unresolved reference: serviceOf
[Incubating] Problems report is available at: file:///home/expo/workingdir/build/android/build/reports/problems/problems-report.html
FAILURE: Build completed with 2 failures.
1: Task failed with an exception.
-----------
* Where:
Build file '/home/expo/workingdir/build/node_modules/@react-native/gradle-plugin/react-native-gradle-plugin/build.gradle.kts' line: 10
* What went wrong:
Script compilation errors:
  Line 10: import org.gradle.configurationcache.extensions.serviceOf
                                                           ^ Unresolved reference: serviceOf
  Line 54:           serviceOf<ModuleRegistry>()
                     ^ Unresolved reference: serviceOf
2 errors
* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.
> Get more help at 
==============================================================================
2: Task failed with an exception.
-----------
* Where:
Build file '/home/expo/workingdir/build/node_modules/@react-native/gradle-plugin/react-native-gradle-plugin/build.gradle.kts' line: 10
* What went wrong:
Script compilation errors:
  Line 10: import org.gradle.configurationcache.extensions.serviceOf
                                                           ^ Unresolved reference: serviceOf
  Line 54:           serviceOf<ModuleRegistry>()
                     ^ Unresolved reference: serviceOf
2 errors
* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.
> Get more help at 
==============================================================================
Deprecated Gradle features were used in this build, making it incompatible with Gradle 9.0.
You can use '--warning-mode all' to show the individual deprecation warnings and determine if they come from your own scripts or plugins.
For more on this, please refer to  in the Gradle documentation.
BUILD FAILED in 42s
Error: Gradle build failed with unknown error. See logs for the "Run gradlew" phase for more information.


Your issue is mainly caused by a massive Expo SDK + React Native version mismatch.

You upgraded/installed some packages, but the project dependencies are mixed between:

old Expo SDK packages
newer Expo SDK 54 packages
old React Native 0.74
expected React Native 0.81
old React 18
expected React 19

That mismatch is what eventually broke Gradle.

The REAL failure is here:

Unresolved reference: serviceOf

inside:

@react-native/gradle-plugin

That usually happens when:

React Native version does not match Gradle plugin version
Expo SDK and RN versions are incompatible
dependencies are partially upgraded

Your project is currently in a "half-upgraded" state.

Main Problems

You currently have:

Package	Installed	Expected
expo	54.0.13	54.0.34
react-native	0.74.5	0.81.5
react	18.2.0	19.1.0

This is a serious incompatibility.

Expo SDK 54 requires:

React 19
RN 0.81
matching Expo libraries

But your app still has old SDK 50/51 style dependencies.

Best Fix (Recommended)

Do NOT manually upgrade package versions one by one.

Instead use Expo installer properly.

Run this:

npx expo install --fix

This is the most important command.

It automatically installs the correct versions matching your Expo SDK.

Then clear everything

After that:

rm -rf node_modules
rm package-lock.json
rm -rf android
rm -rf ios

Windows PowerShell:

Remove-Item -Recurse -Force node_modules
Remove-Item package-lock.json
Remove-Item -Recurse -Force android
Remove-Item -Recurse -Force ios

If using pnpm:

Remove-Item pnpm-lock.yaml
Reinstall
npm install

or

pnpm install
Regenerate native folders

VERY IMPORTANT:

npx expo prebuild --clean

This regenerates Android/iOS native projects with correct versions.

Then build again
eas build -p android --profile preview
Also Update Node.js

You currently have:

v20.11.1

But Expo now requires:

>=20.19.4

Upgrade Node.js to latest LTS:

Node 22 LTS recommended

Download from:

Node.js Official Website

Why This Happened

Most likely:

you upgraded Expo
but old dependencies remained
or copied dependencies from another project
or installed packages with plain npm install

With Expo, always use:

npx expo install package-name

NOT:

npm install package-name

because Expo pins compatible versions internally.

Quickest Recovery Strategy

If the app is still early-stage, honestly the fastest clean fix may be:

npx create-expo-app@latest

then move your:

screens
components
assets
business logic

into fresh project.

Sometimes this is faster than fighting dependency hell.