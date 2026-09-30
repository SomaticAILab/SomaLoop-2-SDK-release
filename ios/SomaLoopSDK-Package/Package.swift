// swift-tools-version:5.10
import PackageDescription
let package=Package(name:"SomaLoopSDK",platforms:[.iOS(.v15)],products:[.library(name:"SomaLoopSDK",targets:["SomaLoopSDK"]),.library(name:"SomaLoopExperimental",targets:["SomaLoopSDK","SomaLoopExperimental"])],targets:[.binaryTarget(name:"SomaLoopSDK",path:"SomaLoopSDK.xcframework"),.binaryTarget(name:"SomaLoopExperimental",path:"SomaLoopExperimental.xcframework")])
