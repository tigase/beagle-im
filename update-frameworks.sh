OPENSSL_FRAMEWORK="OpenSSL.xcframework"
OPENSSL_VERSION="1.1.171"
OPENSSL_CHECKSUM="da438351ed35625802c369a65476b21c7d49bf4a30cce4f91285f925f42bf5b9"
OPENSSL_REPO="tigase/openssl-swiftpm"

WEBRTC_FRAMEWORK="WebRTC.xcframework"
WEBRTC_VERSION="M88"
WEBRTC_CHECKSUM="200ca9e0e2cc861c05a15315c9aaf800b52d44d97d4d2263d889bced59f1dfc6"
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
