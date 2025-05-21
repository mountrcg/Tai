<img src="https://github.com/mountrcg/Trio-dev/blob/Tai-dev/Trio/Resources/Assets.xcassets/app_icons/taiCircledNoBackground.imageset/taiCircledNoBackground.png" width="120">

# **T**rio **a**uto**I**SF fork aka *Tai*

## Introduction of Trio

Trio - an automated insulin delivery system for iOS based on the OpenAPS algorithm with [adaptations for Trio](https://github.com/nightscout/trio-oref).

The project started as Ivan Valkou's [FreeAPS X](https://github.com/ivalkou/freeaps) implementation of the [OpenAPS algorithm](https://github.com/openaps/oref0) for iPhone, and was later forked and rebranded as iAPS. The project has since seen substantial contributions from many developers, leading to a range of new features and enhancements.

Following the release of iAPS version 3.0.0, due to differing views on development, open source, and peer review, there was a significant shift in the project's direction. This led to the separation from the [Artificial-Pancreas/iAPS](https://github.com/Artificial-Pancreas/iAPS) repository, and the birth of [Trio](https://github.com/nightscout/Trio.git) as a distinct entity. 

## What is autoISF?
The vast majority of the autoISF design and development effort was done by [ga-zelle](https://github.com/ga-zelle) with support from
  [swissalpine](https://github.com/swissalpine), [claudi](https://github.com/lutzlukesch),
  [BerNie](https://github.com/bherpichb), [mountrcg](https://github.com/mountrcg),
  [Bjr](https://github.com/blaqone) and [myself](https://github.com/T-o-b-i-a-s).

autoISF adds more power to the oref1 algorithm used in Trio by adjusting the insulin sensitivity based on different scenarios (e.g. high BG,
accelerating/decelerating BG, BG plateau). autoISF has many different settings to fine-tune these adjustments.
However, it is important to start with well-tested basal rate and settings for insulin sensitivity and carb ratios.

*Tai* is based on dev from the original [Trio repo](https://github.com/nightscout/trio) and includes the implementation of [autoISF by ga-zelle](https://github.com/T-o-b-i-a-s/AndroidAPS) for AAPS and some other extra features.

autoISF is off by default.

autoISF adjusts ISF depending on 4 different effects in glucose behaviour that autoISF checks and reacts to:
* acce_ISF is a factor derived from acceleration of glucose levels
* bg_ISF is a factor derived from the deviation of glucose from target
* pp_ISF are factors derived from glucose rise, 5min, 10min and 45min deltas
* dura_ISF is a factor derived from glucose being stuck at high levels

![Bildschirmfoto 2025-01-31 um 13 40 11](https://github.com/user-attachments/assets/dfb4d0b8-b0bc-491d-b391-7e6f645ead0b)

## AIMI B30
Another new feature is an enhanced EatingSoon TT on steroids. It is derived from AAPS AIMI branch and is called B30 (as in basal 30 minutes).
B30 enables an increased basal rate after an EatingSoon TT and a manual bolus. The theory is to saturate the infusion site slowly & consistently with insulin to increase insulin absorption for SMB's following a meal with no carb counting. This of course makes no sense for users striving to go Full Closed Loop (FCL) with autoISF. But for those of you like me, who cannot use Lyumjev or FIASP this is a feature that might speed up your normal insulin and help you to not care about carb counting, using some pre-meal insulin and let autoISF handle the rest.

To use it, it needs 2 conditions besides setting all preferences:
* Setting a TT with a specific adjustable target level.
* A bolus above a specified level, which results in a drastically increased Temp Basal Rate for a short time. If one cancels the TT, also the TBR will cease.

## Ketoacidosis protection
Ketoacidosis protection will apply a small configurable TempBasalRate always or if certain conditions arise instead of a Zero temp! The feature exists because in special cases a person could get ketoacidosis from 0% TBR. The idea is derived from sport. There could be problems when a basal rate of 0% ran for several hours. Muscles in particular could shut off.

This feature enables a small safety TBR to reduce the ketoacidosis risk. Without the Variable Protection Strategy that safety TBR is always applied. The idea behind the variable protection strategy is that the safety TBR is only applied if sum of basal-IOB and bolus-IOB falls negatively below the value of the current basal rate and that current isulin activity is below 0.

## Exercise Modes & Advanced TT's
Exercise Mode with high/low TT can be combined with autoISF. The ratio from the TT, calculated with the Half Basal Exercise target, will be adjusted with the strongest (>1) or weakest (<1) ISF-Ratio from autoISF. This can be substantial. I myself prefer to disable autoISF adjustments while exercising, relying on the TT Ratio, by setting `Exercise toggles all autoISF adjustments off` to on.

Trio has implemented the excercise targets with configurable half basal exercise target variable and a specific desired insulin ratio. This requires highTTraisesSens and lowTTlowersSens setting. You first define at which TT level you want to be. Frome this the available insulin percentages are derived:
* with a TT above 100mg/dL you can only have a insulin percentage below 100% (more sensitive to insulin while exercising)
* If you don't have the setting exercise mode or highTTraisesSens enabled, you will not be able to specify an insulin percentage below 100% with a high TT.
* with a TT below 100 mg/dL you can have an Insulin ratio above 100% (less sensitive to insulin) but less than what your autosens_max setting defines. E.g. if you have autosens_max = 2, that means your increased insulin percentage can be max. 200%.
* If you have lowTTlowersSens disabled or you have autosens_max=1, you cannot specify a percentage >100% for low TTs.

If you do have the appropriate settings, you can chose an insulin ratio with the slider for the TT you have set and the half basal exercise target will be calculated and set in background for the time the TT is active.


# Installation

In Terminal, `cd` to the folder where you want your download to reside, change `<branch>` in the command below to the branch you want to download (ie. `Tai-dev`), and press `return`.

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
- for <img src="Trio/Resources/Assets.xcassets/app_icon_images/catWithPodWhiteBG.imageset/catWithPodWhiteBG 3.png"
     alt="cat"
	 width=200
	 /> only
- and not CE or FDA approved for therapy.


# Documentation

Most of the changes for autoISF are made in oref code of OpenAPS, which is minimized in Tai. So it is not really readable in Xcode, therefore refer to my [oref0-repository](https://github.com/mountrcg/oref0/tree).

## Where to find documentation about autoISF
* Please visit ga-zelle’s repository [GitHub - ga-zelle/autoISF](https://github.com/ga-zelle/autoISF/tree/A3.2.0.4_ai3.0.1).
  The [**Quick Guide (bzw. Kurzanleitung)**](https://github.com/ga-zelle/autoISF/blob/A3.2.0.4_ai3.0.1/autoISF3.0.1_Quick_Guide.pdf) provides an overview of autoISF and its features. All of this is applicable for Tai as the core Algorithm is 100% identical.

[Discord Trio - Server ](https://discord.gg/KepAG6RdYZ)

[Trio documentation](https://docs.diy-trio.org/)

TODO: Add link: Trio Website (under development, not existing yet)

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)

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

For questions or contributions, please join our [Discord server](https://discord.triodocs.org).
