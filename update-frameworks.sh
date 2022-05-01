OPENSSL_FRAMEWORK="OpenSSL.xcframework"
OPENSSL_VERSION="1.1.1400"
OPENSSL_CHECKSUM="ad34827d95048a4b16c66614428e6f077d9a9e4892b8cf2c9fa66ac7ac93f916"
OPENSSL_REPO="tigase/openssl-swiftpm"

WEBRTC_FRAMEWORK="WebRTC.xcframework"
WEBRTC_VERSION="M101"
WEBRTC_CHECKSUM="448f13d912972b2c8af1a99556b5727b372b26b1af51505724d7003999c4b0c7"
WEBRTC_REPO="tigase/webrtc-swiftpm"

testChecksum () {
	retval=0
	local CHECKSUM=($(shasum -a 256 "$1.zip"))
	if [ "$2" != "$CHECKSUM" ]; then
		echo "Checksum of $1 does not match, removing file"
		retval=1
	fi
	return "$retval"
}

downloadFile () {
	echo "Downloading file $1..."
	curl -L "https://github.com/$2/releases/download/$3/$1.zip" -o "$1.zip"
	retval=$?
	return "$retval"
}

downloadIfNeeded () {
	testChecksum $1 $2
	result=$?
	if [ "$result" != "0" ]; then
		rm -rf "$1"
		rm "$1.zip"
		downloadFile $1 $3 $4
		result=$?
		if [ "$result" = "0" ]; then
			testChecksum $1 $2
			result=$?
			if [ "$result" != "0" ]; then
				rm "$1"
				echo "Invalid checksum of downloaded file $1"
				exit $result
			fi
			unzip -q "$1.zip"
		else
			echo "Could not download file $1"
			exit $result
		fi
	fi
}

cd Frameworks

downloadIfNeeded $OPENSSL_FRAMEWORK $OPENSSL_CHECKSUM $OPENSSL_REPO $OPENSSL_VERSION
result=$?
if [ "$result" != "0" ]; then
	echo "Could not update $OPENSSL_FRAMEWORK";
	exit $result;
fi

downloadIfNeeded $WEBRTC_FRAMEWORK $WEBRTC_CHECKSUM $WEBRTC_REPO $WEBRTC_VERSION
result=$?
if [ "$result" != "0" ]; then
	echo "Could not update $WEBRTC_FRAMEWORK";
	exit $result;
fi
