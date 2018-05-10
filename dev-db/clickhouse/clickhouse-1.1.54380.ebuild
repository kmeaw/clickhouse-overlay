# Copyright 1999-2016 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $

EAPI=6

inherit cmake-utils user check-reqs versionator

DESCRIPTION="An OSS column-oriented database management system for real-time data analysis"
HOMEPAGE="https://clickhouse.yandex"
LICENSE="Apache-2.0"
MY_PN="ClickHouse"
if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/yandex/${MY_PN}.git"
	EGIT_SUBMODULES=( -private )
	SRC_URI=""
	TYPE="unstable"
else
	TYPE="stable"
	SRC_URI="https://github.com/yandex/${MY_PN}/archive/v${PV}-${TYPE}.tar.gz -> ${P}.tar.gz
https://github.com/google/cctz/archive/4f9776a.tar.gz -> cctz-4f9776a.tar.gz
https://github.com/edenhill/librdkafka/archive/c3d50eb.tar.gz -> librdkafka-c3d50eb.tar.gz
https://github.com/lz4/lz4/archive/c10863b.tar.gz -> lz4-c10863b.tar.gz
https://github.com/ClickHouse-Extras/zookeeper/archive/438afae.tar.gz -> zookeeper-438afae.tar.gz
https://github.com/facebook/zstd/archive/2555975.tar.gz -> zstd-2555975.tar.gz
https://github.com/Dead2/zlib-ng/archive/e07a52d.tar.gz -> zlib-ng-e07a52d.tar.gz
https://github.com/ClickHouse-Extras/poco/archive/2d5a158.tar.gz -> poco-2d5a158.tar.gz
https://github.com/ClickHouse-Extras/boost/archive/5121cc9.tar.gz -> boost-5121cc9.tar.gz
libressl? ( https://github.com/ClickHouse-Extras/ssl/archive/6fbe1c6.tar.gz -> ssl-6fbe1c6.tar.gz )"
	S="${WORKDIR}/${MY_PN}-${PV}-${TYPE}"
fi

SLOT="0/${TYPE}"
IUSE="+server +client mongodb cpu_flags_x86_sse4_2 libressl"
KEYWORDS="~amd64"

REQUIRED_USE="
	server? ( cpu_flags_x86_sse4_2 )
"

RDEPEND="dev-libs/libltdl[static-libs]
dev-libs/libpcre
client? (
	sys-libs/ncurses:0
	sys-libs/readline:0
)
dev-libs/double-conversion
"

DEPEND="${RDEPEND}
sys-libs/libtermcap-compat[static-libs]
dev-libs/icu[static-libs]
dev-libs/glib[static-libs]
|| ( dev-libs/openssl[static-libs] dev-libs/libressl )
virtual/libmysqlclient[static-libs]
dev-cpp/gtest[static-libs]
dev-libs/re2
dev-libs/capnproto[static-libs]
|| ( >=sys-devel/gcc-7.0 >=sys-devel/clang-3.8 )"

pkg_pretend() {
	CHECKREQS_DISK_BUILD="2G"
	# Actually it is 960M on my machine
	check-reqs_pkg_pretend
	if [[ $(tc-getCC) == clang ]]; then
		:
	elif [[ $(gcc-major-version) -lt 7 ]]; then
		eerror "Compilation with gcc older than 7.0 is not supported"
		die "Too old gcc found."
	fi
}

src_unpack() {
	default_src_unpack
	[[ ${PV} == 9999 ]] && return 0
	cd "${S}/contrib"
	mkdir cctz librdkafka lz4 zookeeper zstd
	tar --strip-components=1 -C cctz -xf "${DISTDIR}/cctz-4f9776a.tar.gz"
	tar --strip-components=1 -C librdkafka -xf "${DISTDIR}/librdkafka-c3d50eb.tar.gz"
	tar --strip-components=1 -C lz4 -xf "${DISTDIR}/lz4-c10863b.tar.gz"
	tar --strip-components=1 -C zookeeper -xf "${DISTDIR}/zookeeper-438afae.tar.gz"
	tar --strip-components=1 -C zstd -xf "${DISTDIR}/zstd-2555975.tar.gz"
	tar --strip-components=1 -C zlib-ng -xf "${DISTDIR}/zlib-ng-e07a52d.tar.gz"
	tar --strip-components=1 -C poco -xf "${DISTDIR}/poco-2d5a158.tar.gz"
	tar --strip-components=1 -C boost -xf "${DISTDIR}/boost-5121cc9.tar.gz"
	use libressl && tar --strip-components=1 -C ssl -xf "${DISTDIR}/ssl-6fbe1c6.tar.gz"
}

src_prepare() {
	default_src_prepare
	#sed -i -r -e "s: -Wno-(for-loop-analysis|unused-local-typedef|unused-private-field): -Wno-unused-variable:g" \
	#	contrib/libpoco/CMakeLists.txt || die "Cannot patch poco"
	if $(tc-getCC) -no-pie -v 2>&1 | grep -q unrecognized; then
		sed -i -e 's:--no-pie::' -i CMakeLists.txt || die "Cannot patch CMakeLists.txt"
		sed -i -e 's:-no-pie::' -i CMakeLists.txt || die "Cannot patch CMakeLists.txt"
	else
		sed -i -e 's:--no-pie:-no-pie:' -i CMakeLists.txt || die "Cannot patch CMakeLists.txt"
	fi

	sed -i -- "s/VERSION_REVISION .*)/VERSION_REVISION ${PV##*.})/g" dbms/cmake/version.cmake
	sed -i -- "s/VERSION_DESCRIBE .*)/VERSION_DESCRIBE v${PV}-${TYPE})/g" dbms/cmake/version.cmake
}

src_configure() {
	DISABLE_MONGODB=1
	use mongodb && DISABLE_MONGODB=0
	export DISABLE_MONGODB
	local mycmakeargs=(
		-D CMAKE_BUILD_TYPE:STRING=Release
		-D USE_STATIC_LIBRARIES:BOOL=False
		-D ENABLE_TESTS:BOOL=False
		-D UNBUNDLED:BOOL=False
		-D USE_INTERNAL_DOUBLE_CONVERSION_LIBRARY:BOOL=False
		-D USE_INTERNAL_CAPNP_LIBRARY:BOOL=False
		-D USE_INTERNAL_POCO_LIBRARY:BOOL=True
		-D POCO_STATIC:BOOL=True
		-D USE_INTERNAL_RE2_LIBRARY:BOOL=False
	)
	use libressl && mycmakeargs+=( -D USE_INTERNAL_SSL_LIBRARY:BOOL=True )
	cmake-utils_src_configure
}

src_compile() {
	cmake-utils_src_compile clickhouse
}

src_install() {
	cd "${BUILD_DIR}"
	einfo $(pwd)
	scanelf -BXrq dbms/src/Server/clickhouse
	scanelf -BXrq dbms/libclickhouse.so.1

	if use server; then
		exeinto /usr/sbin
		newexe dbms/src/Server/clickhouse clickhouse-server
		newinitd "${FILESDIR}"/clickhouse-server.initd clickhouse

		exeinto /usr/$(get_libdir)
		doexe dbms/libclickhouse.so.1

		insinto /etc/clickhouse-server
		doins "${S}"/dbms/src/Server/config.xml
		doins "${S}"/dbms/src/Server/users.xml

		sed -e 's:/opt/clickhouse:/var/lib/clickhouse:g' -i "${ED}/etc/clickhouse-server/config.xml"
		sed -e '/listen_host/s%::<%::1<%' -i "${ED}/etc/clickhouse-server/config.xml"

		dodir /var/lib/clickhouse/data/default /var/lib/clickhouse/metadata/default /var/lib/clickhouse/tmp
		dodir /var/log/clickhouse-server
		fowners -R clickhouse:clickhouse /var/lib/clickhouse
		fperms -R 0750 /var/lib/clickhouse
		fowners -R clickhouse:adm /var/log/clickhouse-server
		fperms -R 0750 /var/log/clickhouse-server
	fi

	if use client; then
		exeinto /usr/bin
		newexe dbms/src/Server/clickhouse clickhouse-client

		insinto /etc/clickhouse-client
		newins "${S}"/dbms/src/Server/clickhouse-client.xml config.xml
	fi
}

pkg_setup() {
	if use server; then
		enewgroup clickhouse
		enewuser clickhouse -1 -1 /var/lib/clickhouse clickhouse
	fi
}
