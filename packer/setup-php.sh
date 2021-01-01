#!/bin/bash -eux

PHP_INI_DIR=/usr/local/etc/php
mkdir -p "$PHP_INI_DIR/conf.d"

PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
PHP_CPPFLAGS="$PHP_CFLAGS"
PHP_LDFLAGS="-Wl,-O1 -pie"
PHP_EXTRA_CONFIGURE_ARGS="--with-apxs2 --disable-cgi"

CFLAGS="$PHP_CFLAGS"
CPPFLAGS="$PHP_CPPFLAGS"
LDFLAGS="$PHP_LDFLAGS"

cd /usr/src/php
gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"
# https://bugs.php.net/bug.php?id=74125
if [ ! -d /usr/include/curl ]; then
	ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl
fi
# https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions
./configure \
	--build="$gnuArch" \
	--enable-ftp \
	--enable-mbstring \
	--enable-mysqlnd \
	--enable-option-checking=fatal \
	--with-config-file-path="$PHP_INI_DIR" \
	--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
	--with-curl \
	--with-libdir="lib/$debMultiarch" \
	--with-libedit \
	--with-mhash \
	--with-openssl \
	--with-password-argon2 \
    --with-pear \
	--with-pdo-sqlite=/usr \
	--with-pic \
	--with-sodium=shared \
	--with-sqlite3=/usr \
	--with-zip \
	--with-zlib \
    --enable-bcmath \
    --enable-exif \
    --enable-gd \
    --with-freetype \
    --with-jpeg \
    --with-mysqli \
	${PHP_EXTRA_CONFIGURE_ARGS:-}
make -j "$(nproc)"
find -type f -name '*.a' -delete
make install
find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true
make clean
