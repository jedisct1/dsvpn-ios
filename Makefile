.PHONY: generate build lint clean

generate:
	tuist generate

build: generate
	xcodebuild -workspace dsvpn.xcworkspace -scheme dsvpn -sdk iphoneos build

lint:
	swiftlint lint --quiet

clean:
	xcodebuild -workspace dsvpn.xcworkspace -scheme dsvpn clean
	rm -rf Derived build
