**T**rio **a**uto**i**sf fork aka **Tai**

# Introduction of Trio

Trio - an automated insulin delivery system for iOS based on the OpenAPS algorithm with [adaptations for Trio](https://github.com/nightscout/trio-oref).

The project started as Ivan Valkou's [FreeAPS X](https://github.com/ivalkou/freeaps) implementation of the [OpenAPS algorithm](https://github.com/openaps/oref0) for iPhone, and was later forked and rebranded as iAPS. The project has since seen substantial contributions from many developers, leading to a range of new features and enhancements.

Following the release of iAPS version 3.0.0, due to differing views on development, open source, and peer review, there was a significant shift in the project's direction. This led to the separation from the [Artificial-Pancreas/iAPS](https://github.com/Artificial-Pancreas/iAPS) repository, and the birth of [Trio](https://github.com/nightscout/Trio.git) as a distinct entity. This transition marks a new phase for the project, symbolizing both its evolution and the dynamic nature of collaborative development.

Trio continues to leverage a variety of frameworks from the DIY looping community and remains at the forefront of DIY diabetes management solutions, constantly evolving with valuable contributions from its community.

## autoISF

$${\color{green}I \space will \space switch \space permanently \space from \space iAPS \space to \space this \space Trio \space based \space fork,}$$

$${\color{green}ultimatly \space there \space is \space more \space cooperation, \space discussion, \space talent \space and \space very \space importantly \space better \space vibes \space in \space the \space community.}$$ 

Tai is based on dev from the original [Trio repo](https://github.com/nightscout/trio) and includes my implementation of [autoISF by ga-zelle](https://github.com/T-o-b-i-a-s/AndroidAPS) for AAPS and some other extra features. autoISF is off by default.

autoISF adjusts ISF depending on 4 different effects in glucose behaviour that autoISF checks and reacts to:
* acce_ISF is a factor derived from acceleration of glucose levels
* bg_ISF is a factor derived from the deviation of glucose from target
* delta_ISF and pp_ISF are factors derived from glucose rise, 5min, 10min and 45min deltas and postprandial time frames
* dura_ISF is a factor derived from glucose being stuck at high levels

## AIMI B30
Another new feature is an enhanced EatingSoon TT on steroids. It is derived from AAPS AIMI branch and is called B30 (as in basal 30 minutes).
B30 enables an increased basal rate after an EatingSoon TT and a manual bolus. The theory is to saturate the infusion site slowly & consistently with insulin to increase insulin absorption for SMB's following a meal with no carb counting. This of course makes no sense for users striving to go Full Closed Loop (FCL) with autoISF. But for those of you like me, who cannot use Lyumjev or FIASP this is a feature that might speed up your normal insulin and help you to not care about carb counting, using some pre-meal insulin and let autoISF handle the rest.

To use it, it needs 2 conditions besides setting all preferences:
* Setting a TT with a specific adjustable target level.
* A bolus above a specified level, which results in a drastically increased Temp Basal Rate for a short time. If one cancels the TT, also the TBR will cease.

## To download this repo:

You can either use the Build Script or you can run each command manually.

### Command Line Interface (CLI):

In Terminal, `cd` to the folder where you want your download to reside, change `<branch>` in the command below to the branch you want to download (ie. `tai` or `dev-tai`), and press `return`.

```
git clone --branch=<branch> --recurse-submodules https://github.com/mountrcg/Trio.git && cd Trio
```

Create a ConfigOverride.xcconfig file that contains your Apple Developer ID (something like `123A4BCDE5`). This will automate signing of the build targets in Xcode:

Copy the command below, and replace `xxxxxxxxxx` by your Apple Developer ID before running the command in Terminal.
```
echo 'DEVELOPER_TEAM = xxxxxxxxxx' > ConfigOverride.xcconfig
```

Then launch Xcode and build the Tai app:
```
xed .
```

## To build directly in GitHub, without using Xcode:

Instructions:

For main branch:
* https://github.com/nightscout/Trio/blob/tai/fastlane/testflight.md

For dev branch:
* https://github.com/nightscout/Trio/blob/dev-tai/fastlane/testflight.md

Instructions in greater detail, but not Trio-specific:
* https://loopkit.github.io/loopdocs/gh-actions/gh-overview/

## Please understand that Trio with autoISF aka Tai:
- is an open-source system developed by enthusiasts and for use at your own risk
- for <img src="FreeAPS/Resources/Assets.xcassets/catWithPodWhiteBG.appiconset/catWithPodWhiteBG1024x1024%201.png"
     alt="cat"
	 width=200
	 /> only
- and not CE or FDA approved for therapy.


# Documentation

Most of the changes for autoISF are made in oref code of OpenAPS, which is minimized in Tai. So it is not really readable in Xcode, therefore refer to my [oref0-repository](https://github.com/mountrcg/oref0/tree).

[Documentation of autoISF implementation for AAPS](https://github.com/ga-zelle/autoISF) is applicable for Tai as Algorithm is 100% identical

[AAPS autoISF Branch](https://github.com/T-o-b-i-a-s/AndroidAPS)

[Discord Trio - Server ](https://discord.gg/KepAG6RdYZ)

[Trio documentation](https://docs.diy-trio.org/en/latest/)

TODO: Add link: Trio Website (under development, not existing yet)

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)

TODO: Add link and status graphic: Crowdin Project for translation of Trio (not existing yet)

# Support

Not a lot, only some enthusiasts at [FCL & autoISF Discord](https://discord.gg/KUa8Nf2eeU)

# Contribute

If you would like to give something back to the Trio community, there are several ways to contribute:

## Pay it forward
When you have successfully built Trio and managed to get it working well for your diabetes management, it's time to pay it forward.
You can start by responding to questions in the Facebook or Discord support groups, helping others make the best out of Trio.

## Translate
Trio is translated into several languages to make sure it's easy to understand and use all over the world.
Translation is done using [Crowdin](https://crowdin.com/project/trio), and does not require any programming skills.
If your preferred language is missing or you'd like to improve the translation, please sign up as a translator on [Crowdin](https://crowdin.com/project/trio).

## Develop
Do you speak JS or Swift? Do you have UI/UX skills? Do you know how to optimize API calls or improve data storage? Do you have experience with testing and release management?
Trio is a collaborative project. We always welcome fellow enthusiasts who can contribute with new code, UI/UX improvements, code reviews, testing and release management.
If you want to contribute to the development of Trio, please reach out on Discord or Facebook.

For questions or contributions, please join our [Discord server](https://discord.gg/KepAG6RdYZ).
