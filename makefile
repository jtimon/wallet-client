
ROOT=$(shell pwd)
CACHE=${ROOT}/.cache
PYENV=${ROOT}/.pyenv
JSENV=${ROOT}/.jsenv
RBENV=${ROOT}/.rbenv
SYSROOT=${ROOT}/.sysroot
CONF=${ROOT}/conf
APP_NAME=wallet
PACKAGE=wallet

-include Makefile.local

.PHONY: all
all: python-env ruby-env nodejs-env secret-keys vm bower-pkgs

.PHONY: vm
vm: HyperDex-vm PostgreSQL-vm

.PHONY: db
db: vm
	for app in `.pyenv/bin/python -c \
	"from wallet import app; print ' '.join(app.config['INSTALLED_APPS']);"`; do \
	    DIRECTORY=`echo $$app | sed -e 's:\.:/:g'`/migrations; \
	    if [ -d $$DIRECTORY ]; then \
	        "${PYENV}"/bin/python "${ROOT}"/manage.py db upgrade -d $$DIRECTORY; \
	    fi \
	done

	if [ "x`${PYENV}/bin/python -c 'from wallet import db; from apps.auth.db.models import User; print(db.session.query(db.exists().where(User.active==True)).scalar())'`" = "xFalse" ]; then \
	    echo "\n  It appears that no superuser account has been created."; \
	    echo "  At some point in the future, this text will be replaced"; \
	    echo "  with a script to create the first superuser account.\n"; \
	fi

.PHONY: check
check: all
	mkdir -p build/report/xunit
	@echo  >.pytest.py "import unittest2"
	@echo >>.pytest.py "import xmlrunner"
	@echo >>.pytest.py "unittest2.main("
	@echo >>.pytest.py "    testRunner=xmlrunner.XMLTestRunner("
	@echo >>.pytest.py "        output='build/report/xunit'),"
	@echo >>.pytest.py "    argv=['unit2', 'discover',"
	@echo >>.pytest.py "        '-s','py',"
	@echo >>.pytest.py "        '-p','*.py',"
	@echo >>.pytest.py "        '-t','test',"
	@echo >>.pytest.py "    ]"
	@echo >>.pytest.py ")"
	chmod +x .pytest.py
	"${PYENV}"/bin/coverage run .pytest.py || { rm -f .pytest.py; exit 1; }
	"${PYENV}"/bin/coverage xml --omit=".pytest.py" -o build/report/coverage.xml
	-rm -f .pytest.py

.PHONY: shell
shell: all
	"${PYENV}"/bin/python "${ROOT}"/manage.py shell

.PHONY: run-dummy run-hyperdex run-postgres run-hyperdex-p run-postgres-p
run-hyperdex: hyperdex.env hyperdex.proc run
run-postgres: postgres.env postgres.proc run
run-dummy: proxy.proc dummy.env dummy.proc run
run-hyperdex-p: proxy.proc hyperdex-proxy.env hyperdex.proc run
run-postgres-p: proxy.proc postgres-proxy.env postgres.proc run

base.env: 
	cat "${CONF}"/development.proc > "${ROOT}"/.Procfile.target
	cat "${CONF}"/development.env > "${ROOT}"/.env
%.env: base.env
	if [ -e "${CONF}"/$@ ] ; then cat "${CONF}"/$@ >> "${ROOT}"/.env ; fi
%.proc: base.env
	if [ -e "${CONF}"/$@ ] ; then cat "${CONF}"/$@ >> "${ROOT}"/.Procfile.target ; fi

.PHONY: run
run: all base.env
	bash -c "source '${PYENV}'/bin/activate && \
	    RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv exec bundle exec \
	        foreman start --port=8100 --root="${ROOT}" \
	                      --env "${ROOT}"/.env \
	                      --procfile "${ROOT}"/.Procfile.target"

.PHONY: mostlyclean
mostlyclean:
	-rm -rf dist
	-rm -rf build
	-rm -rf .coverage
	-rm -rf .build

.PHONY: clean
clean: mostlyclean
	-rm -f .rbenv-version
	-rm -rf "${RBENV}"
	-rm -rf "${PYENV}"
	-rm -rf "${JSENV}"
	-rm -rf "${SYSROOT}"

.PHONY: distclean
distclean: clean
	-rm -rf "${CACHE}"
	-rm -rf Makefile.local

.PHONY: maintainer-clean
maintainer-clean: distclean
	@echo 'This command is intended for maintainers to use; it'
	@echo 'deletes files that may need special tools to rebuild.'

# ===----------------------------------------------------------------------===

.PHONY: secret-keys
secret-keys: ${ROOT}/${PACKAGE}/settings/secret_keys.py

${ROOT}/${PACKAGE}/settings/secret_keys.py:
	@echo  >"${ROOT}/${PACKAGE}"/secret_keys.py '# -*- coding: utf-8 -*-'
	@echo >>"${ROOT}/${PACKAGE}"/secret_keys.py \
	    "SECRET_KEY             = '`LC_CTYPE=C < /dev/urandom tr -dc A-Za-z0-9_ | head -c24`'"
	@echo >>"${ROOT}/${PACKAGE}"/secret_keys.py \
	    "SECURITY_PASSWORD_SALT = '`LC_CTYPE=C < /dev/urandom tr -dc A-Za-z0-9_ | head -c24`'"
	@echo >>"${ROOT}/${PACKAGE}"/secret_keys.py \
	    "SECURITY_CONFIRM_SALT  = '`LC_CTYPE=C < /dev/urandom tr -dc A-Za-z0-9_ | head -c24`'"
	@echo >>"${ROOT}/${PACKAGE}"/secret_keys.py \
	    "SECURITY_RESET_SALT    = '`LC_CTYPE=C < /dev/urandom tr -dc A-Za-z0-9_ | head -c24`'"
	@echo >>"${ROOT}/${PACKAGE}"/secret_keys.py \
	    "SECURITY_LOGIN_SALT    = '`LC_CTYPE=C < /dev/urandom tr -dc A-Za-z0-9_ | head -c24`'"
	@echo >>"${ROOT}/${PACKAGE}"/secret_keys.py \
	    "SECURITY_REMEMBER_SALT = '`LC_CTYPE=C < /dev/urandom tr -dc A-Za-z0-9_ | head -c24`'"

# ===--------------------------------------------------------------------===

.PHONY: bower-pkgs
bower-pkgs: ${ROOT}/app/.stamp-h

${ROOT}/app/.stamp-h: ${ROOT}/.bowerrc ${ROOT}/bower.json
	bash -c "cd conf && "${JSENV}"/bin/bower install"
	touch "$@"

# ===--------------------------------------------------------------------===

${ROOT}/db/HyperDex/.stamp-h: ${SYSROOT}/.stamp-HyperDex-h
	-$(MAKE) HyperDex-destroy
	mkdir -p "${ROOT}"/db/HyperDex/coordinator-{1,2,3,4,5}
	mkdir -p "${ROOT}"/db/HyperDex/daemon-{1,2,3}
	touch "$@"

.PHONY: HyperDex-vm
HyperDex-vm: ${ROOT}/db/HyperDex/.stamp-h

.PHONY: HyperDex-destroy
HyperDex-destroy:
	rm -rf "${ROOT}"/db/HyperDex

# ===--------------------------------------------------------------------===

${ROOT}/db/PostgreSQL/.stamp-h:
	-$(MAKE) PostgreSQL-destroy
	mkdir -p "${ROOT}"/db/PostgreSQL
	initdb \
	    -D "${ROOT}"/db/PostgreSQL \
	    --encoding         UTF-8 \
	    --locale     en_US.UTF-8 \
	    --lc-collate en_US.UTF-8 \
	    --lc-ctype   en_US.UTF-8 \
	    --data-checksums \
	    || { rm -rf "${ROOT}/db/PostgreSQL"; exit 1; }
	sed -e "s:#port = 5432:port = 2080:" \
	    db/PostgreSQL/postgresql.conf >pg.tmp
	mv  pg.tmp  db/PostgreSQL/postgresql.conf
	sed -e "s:#unix_socket_directories = '.*':unix_socket_directories = '${ROOT}/db/PostgreSQL':" \
	    db/PostgreSQL/postgresql.conf >pg.tmp
	mv  pg.tmp  db/PostgreSQL/postgresql.conf
	pg_ctl start -w -U `whoami` -D "${ROOT}"/db/PostgreSQL
	psql -h "${ROOT}"/db/PostgreSQL -p 2080 postgres \
	    -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
	psql -h "${ROOT}"/db/PostgreSQL -p 2080 template1 \
	    -c "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
	psql -h "${ROOT}"/db/PostgreSQL -p 2080 postgres \
	    -c "CREATE USER wallet WITH PASSWORD 'password';"
	psql -h "${ROOT}"/db/PostgreSQL -p 2080 postgres \
	        -c "ALTER ROLE wallet WITH CREATEDB;"
	psql -h "${ROOT}"/db/PostgreSQL -p 2080 postgres \
	        -c "CREATE DATABASE wallet;"
	psql -h "${ROOT}"/db/PostgreSQL -p 2080 postgres \
	        -c "GRANT ALL PRIVILEGES ON DATABASE wallet TO wallet;"
	touch "$@"

.PHONY: PostgreSQL-vm
PostgreSQL-vm: ${ROOT}/db/PostgreSQL/.stamp-h

.PHONY: PostgreSQL-shell
PostgreSQL-shell: PostgreSQL-vm
	PGPASSWORD=password psql -h localhost -p 2080 -U wallet wallet

.PHONY: PostgreSQL-destroy
PostgreSQL-destroy:
	rm -rf "${ROOT}/db/PostgreSQL"

# ===--------------------------------------------------------------------===

.PHONY: rabbitmq-vm
rabbitmq-vm:
	bash -c "cd '${CONF}' && vagrant up rabbitmq --no-provision"
	${PYENV}/bin/python -c "import amqp; amqp.Connection('localhost:11871', 'bunny', 'password', virtual_host='wallet')" || \
	    bash -c "cd '${CONF}' && vagrant reload rabbitmq"

.PHONY: rabbitmq-ssh
rabbitmq-ssh: rabbitmq
	bash -c "cd '${CONF}' && vagrant ssh rabbitmq"

.PHONY: rabbitmq-shell
rabbitmq-shell: rabbitmq

.PHONY: rabbitmq-destroy
rabbitmq-destroy:

# ===--------------------------------------------------------------------===

${CONF}/vm/riak/cache/otp_src_R15B01.tar.gz:
	mkdir -p "${CONF}"/vm/riak/cache
	curl -L 'http://pkgs.fedoraproject.org/repo/pkgs/erlang/otp_src_R15B01.tar.gz/f12d00f6e62b36ad027d6c0c08905fad/otp_src_R15B01.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CONF}/vm/riak/cache/riak-1.4.2.tar.gz:
	mkdir -p "${CONF}"/vm/riak/cache
	curl -L 'http://s3.amazonaws.com/downloads.basho.com/riak/1.4/1.4.2/riak-1.4.2.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

.PHONY: riakvm
riakvm: ${CONF}/vm/riak/cache/otp_src_R15B01.tar.gz ${CONF}/vm/riak/cache/riak-1.4.2.tar.gz
	bash -c "cd '${CONF}' && vagrant up riak --no-provision"
	false || \
	    bash -c "cd '${CONF}' && vagrant reload riak"

.PHONY: riak
riak: riakvm

.PHONY: riakssh
riakssh: riak
	bash -c "cd '${CONF}' && vagrant ssh riak"

.PHONY: riakshell
riakshell: riak

.PHONY: riakdestroy
riakdestroy:

# ===--------------------------------------------------------------------===

${CACHE}/pyenv/virtualenv-1.10.1.tar.gz:
	mkdir -p "${CACHE}"/pyenv
	curl -L 'https://pypi.python.org/packages/source/v/virtualenv/virtualenv-1.10.1.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/pyenv/pyenv-1.10.1-base.tar.gz: ${CACHE}/pyenv/virtualenv-1.10.1.tar.gz
	-rm -rf "${PYENV}"
	mkdir -p "${PYENV}"

	# virtualenv is used to create a separate Python installation
	# for this project in ${PYENV}.
	tar \
	    -C "${CACHE}"/pyenv --gzip \
	    -xf "${CACHE}"/pyenv/virtualenv-1.10.1.tar.gz
	python "${CACHE}"/pyenv/virtualenv-1.10.1/virtualenv.py \
	    --clear \
	    --distribute \
	    --never-download \
	    --prompt="(${APP_NAME}) " \
	    "${PYENV}"
	-rm -rf "${CACHE}"/pyenv/virtualenv-1.10.1

	# Snapshot the Python environment
	tar -C "${PYENV}" --gzip -cf "$@" .
	rm -rf "${PYENV}"

${CACHE}/pyenv/pyenv-1.10.1-extras.tar.gz: ${CACHE}/pyenv/pyenv-1.10.1-base.tar.gz ${ROOT}/requirements.txt ${CONF}/requirements*.txt ${SYSROOT}/.stamp-gmp-h ${SYSROOT}/.stamp-mpfr-h ${SYSROOT}/.stamp-mpc-h
	-rm -rf "${PYENV}"
	mkdir -p "${PYENV}"
	mkdir -p "${CACHE}"/pypi

	# Uncompress saved Python environment
	tar -C "${PYENV}" --gzip -xf "${CACHE}"/pyenv/pyenv-1.10.1-base.tar.gz
	find "${PYENV}" -not -type d -print0 >"${ROOT}"/.pkglist

	# readline is installed here to get around a bug on Mac OS X
	# which is causing readline to not build properly if installed
	# from pip, and the fact that a different package must be used
	# to support it on Windows/Cygwin.
	if [ "x`uname -s`" = "xCygwin" ]; then \
	    "${PYENV}"/bin/pip install pyreadline; \
	else \
	    "${PYENV}"/bin/easy_install readline; \
	fi

	# Install Python ZeroMQ bindings using easy_install, so it can
	# grab the pre-compiled binaries from PyPI.
	"${PYENV}"/bin/easy_install pyzmq

	# pip is used to install Python dependencies for this project.
	for reqfile in "${ROOT}"/requirements.txt \
	               "${CONF}"/requirements*.txt; do \
	    CFLAGS="-I'${SYSROOT}'/include" \
	    LDFLAGS="-L'${SYSROOT}'/lib" \
	    "${PYENV}"/bin/python "${PYENV}"/bin/pip install \
	        --download-cache="${CACHE}"/pypi \
	        -r "$$reqfile" || exit 1; \
	done

	# Snapshot the Python environment
	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${PYENV}" --gzip -cf "$@" .
	rm -rf "${PYENV}" "${ROOT}"/.pkglist

.PHONY:
python-env: ${PYENV}/.stamp-h

${PYENV}/.stamp-h: ${CACHE}/pyenv/pyenv-1.10.1-base.tar.gz ${CACHE}/pyenv/pyenv-1.10.1-extras.tar.gz
	-rm -rf "${PYENV}"
	mkdir -p "${PYENV}"

	# Uncompress saved Python environment
	tar -C "${PYENV}" --gzip -xf "${CACHE}"/pyenv/pyenv-1.10.1-base.tar.gz
	tar -C "${PYENV}" --gzip -xf "${CACHE}"/pyenv/pyenv-1.10.1-extras.tar.gz

	# Install the HyperDex bindings, if they exist
	$(MAKE) HyperDex-python-bindings

	# Install the project package as a Python egg:
	"${PYENV}"/bin/python "${ROOT}"/setup.py develop

	# All done!
	touch "$@"

HyperDex-python-bindings:
	if [ -d "${SYSROOT}"/lib/python?.?/site-packages/hyperdex ]; then \
	    cp -Rf "${SYSROOT}"/lib/python?.?/site-packages/*hyperdex* \
	           "`'${PYENV}'/bin/python -c 'from distutils.sysconfig import get_python_lib; print(get_python_lib())'`"; \
	fi

# ===--------------------------------------------------------------------===

${CACHE}/jsenv/node-v0.10.23.tar.gz:
	mkdir -p "${CACHE}"/jsenv
	curl -L 'http://nodejs.org/dist/v0.10.23/node-v0.10.23.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/jsenv/jsenv-0.10.23-base.tar.gz: ${CACHE}/jsenv/node-v0.10.23.tar.gz
	-rm -rf "${JSENV}"
	mkdir -p "${JSENV}"

	rm -rf "${ROOT}"/.build/nodejs
	mkdir -p "${ROOT}"/.build/nodejs
	tar -C "${ROOT}"/.build/nodejs --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/nodejs && ./configure --prefix '${JSENV}'"
	bash -c "cd '${ROOT}'/.build/nodejs && make all install"
	rm -rf "${ROOT}"/.build/nodejs

	# Snapshot the node.js environment
	tar -C "${JSENV}" --gzip -cf "$@" .
	rm -rf "${JSENV}"

${CACHE}/jsenv/jsenv-0.10.23-extras.tar.gz: ${CACHE}/jsenv/jsenv-0.10.23-base.tar.gz ${ROOT}/npm-pkgs.txt
	-rm -rf "${JSENV}"
	mkdir -p "${JSENV}"

	# Uncompress saved node.js environment
	tar -C "${JSENV}" --gzip -xf "${CACHE}"/jsenv/jsenv-0.10.23-base.tar.gz
	find "${JSENV}" -not -type d -print0 >"${ROOT}"/.pkglist

	# npm is used to install node.js dependencies for this project.
	# npm-shrinkwrap makes `npm install` use the versions specified in
	# npm-shrinkwrap.json
	"${JSENV}"/bin/npm config set cache "${CACHE}"/npm
	while read pkg; do \
	    "${JSENV}"/bin/npm install -g $$pkg; \
	done < "${ROOT}"/npm-pkgs.txt

	# Snapshot the node.js environment
	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${JSENV}" --gzip -cf "$@" .
	rm -rf "${JSENV}" "${ROOT}"/.pkglist

.PHONY:
nodejs-env: ${JSENV}/.stamp-h

${JSENV}/.stamp-h: ${CACHE}/jsenv/jsenv-0.10.23-base.tar.gz ${CACHE}/jsenv/jsenv-0.10.23-extras.tar.gz
	-rm -rf "${JSENV}"
	mkdir -p "${JSENV}"

	# Uncompress saved node.js environment
	tar -C "${JSENV}" --gzip -xf "${CACHE}"/jsenv/jsenv-0.10.23-base.tar.gz
	tar -C "${JSENV}" --gzip -xf "${CACHE}"/jsenv/jsenv-0.10.23-extras.tar.gz

	# All done!
	touch "$@"

# ===----------------------------------------------------------------------===

${CACHE}/rbenv/rbenv-0.4.0.tar.gz:
	mkdir -p ${CACHE}/rbenv
	curl -L 'https://codeload.github.com/sstephenson/rbenv/tar.gz/v0.4.0' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/rbenv/ruby-build-20131028.tar.gz:
	mkdir -p ${CACHE}/rbenv
	curl -L 'https://codeload.github.com/sstephenson/ruby-build/tar.gz/v20131028' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/rbenv/yaml-0.1.4.tar.gz:
	mkdir -p ${CACHE}/rbenv
	curl -L 'http://dqw8nmjcqpjn7.cloudfront.net/36c852831d02cf90508c29852361d01b' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/rbenv/ruby-1.9.3-p448.tar.gz:
	mkdir -p ${CACHE}/rbenv
	curl -L 'http://dqw8nmjcqpjn7.cloudfront.net/a893cff26bcf351b8975ebf2a63b1023' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/rbenv/rbenv-1.9.3-p448-base.tar.gz: ${CACHE}/rbenv/rbenv-0.4.0.tar.gz ${CACHE}/rbenv/ruby-build-20131028.tar.gz ${CACHE}/rbenv/yaml-0.1.4.tar.gz ${CACHE}/rbenv/ruby-1.9.3-p448.tar.gz
	-rm -rf "${RBENV}"
	mkdir -p "${RBENV}"

	# rbenv (and its plugins, ruby-build and rbenv-gemset) is used to build,
	# install, and manage ruby environments:
	tar \
	    -C "${RBENV}" --strip-components 1 --gzip \
	    -xf "${CACHE}"/rbenv/rbenv-0.4.0.tar.gz
	mkdir -p "${RBENV}"/plugins/ruby-build
	tar \
	    -C "${RBENV}"/plugins/ruby-build --strip-components 1 --gzip \
	    -xf "${CACHE}"/rbenv/ruby-build-20131028.tar.gz

	mkdir -p "${RBENV}"/cache
	ln -s "${CACHE}"/rbenv/yaml-0.1.4.tar.gz      "${RBENV}"/cache
	ln -s "${CACHE}"/rbenv/ruby-1.9.3-p448.tar.gz "${RBENV}"/cache

	# Trigger a build and install of our required ruby version:
	if [ "x`uname -s`" = "xDarwin" ]; then \
	    CONFIGURE_OPTS=--without-gcc \
	    RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv install 1.9.3-p448; \
	else \
	    RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv install 1.9.3-p448; \
	fi
	- RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv rehash
	echo 1.9.3-p448 >"${RBENV}"/.rbenv-version

	# Snapshot the Ruby environment
	tar -C "${RBENV}" --gzip -cf "$@" .
	rm -rf "${RBENV}"

Gemfile.lock: Gemfile
	touch "$@"
${CACHE}/rbenv/rbenv-1.9.3-p448-extras.tar.gz: ${CACHE}/rbenv/rbenv-1.9.3-p448-base.tar.gz Gemfile.lock
	-rm -rf "${RBENV}"
	mkdir -p "${RBENV}"

	# Uncompress saved Ruby environment
	tar -C "${RBENV}" --gzip -xf "${CACHE}"/rbenv/rbenv-1.9.3-p448-base.tar.gz
	mv "${RBENV}"/.rbenv-version "${ROOT}"

	find "${RBENV}" -not -type d -print0 >"${ROOT}"/.pkglist

	# Install bundler & gemset dependencies:
	  RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv exec gem install bundler
	- RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv rehash
	  RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv exec bundle install
	- RBENV_ROOT="${RBENV}" "${RBENV}"/bin/rbenv rehash

	# Snapshot the Ruby environment
	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${RBENV}" --gzip -cf "$@" .
	rm -rf "${RBENV}" "${ROOT}"/.pkglist

.PHONY:
ruby-env: ${RBENV}/.stamp-h

${RBENV}/.stamp-h: ${CACHE}/rbenv/rbenv-1.9.3-p448-base.tar.gz ${CACHE}/rbenv/rbenv-1.9.3-p448-extras.tar.gz
	-rm -rf "${RBENV}"
	mkdir -p "${RBENV}"

	# Uncompress saved Ruby environment
	tar -C "${RBENV}" --gzip -xf "${CACHE}"/rbenv/rbenv-1.9.3-p448-base.tar.gz
	tar -C "${RBENV}" --gzip -xf "${CACHE}"/rbenv/rbenv-1.9.3-p448-extras.tar.gz
	mv "${RBENV}"/.rbenv-version "${ROOT}"

	# All done!
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/gmp/gmp-5.1.3.tar.xz:
	mkdir -p ${CACHE}/gmp
	curl -L 'https://ftp.gnu.org/gnu/gmp/gmp-5.1.3.tar.xz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/gmp/gmp-5.1.3-pkg.tar.gz: ${CACHE}/gmp/gmp-5.1.3.tar.xz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"

	rm -rf "${ROOT}"/.build/gmp
	mkdir -p "${ROOT}"/.build/gmp
	tar -C "${ROOT}"/.build/gmp --strip-components 1 --xz -xf "$<"
	bash -c "cd '${ROOT}'/.build/gmp && ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/gmp && make all install"
	rm -rf "${ROOT}"/.build/gmp

	# Snapshot the package
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: gmp-pkg
gmp-pkg: ${SYSROOT}/.stamp-gmp-h
${SYSROOT}/.stamp-gmp-h: ${CACHE}/gmp/gmp-5.1.3-pkg.tar.gz
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/mpfr/mpfr-3.1.2.tar.xz:
	mkdir -p ${CACHE}/mpfr
	curl -L 'http://ftp.gnu.org/gnu/mpfr/mpfr-3.1.2.tar.xz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/mpfr/mpfr-3.1.2-pkg.tar.gz: ${CACHE}/mpfr/mpfr-3.1.2.tar.xz ${CACHE}/gmp/gmp-5.1.3-pkg.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/gmp/gmp-5.1.3-pkg.tar.gz
	find "${SYSROOT}" -not -type d -print0 >"${ROOT}"/.pkglist

	rm -rf "${ROOT}"/.build/mpfr
	mkdir -p "${ROOT}"/.build/mpfr
	tar -C "${ROOT}"/.build/mpfr --strip-components 1 --xz -xf "$<"
	bash -c "cd '${ROOT}'/.build/mpfr && ./configure \
	    --prefix '${SYSROOT}' \
	    --with-gmp='${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/mpfr && make all install"
	rm -rf "${ROOT}"/.build/mpfr

	# Snapshot the package
	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: mpfr-pkg
mpfr-pkg: ${SYSROOT}/.stamp-mpfr-h
${SYSROOT}/.stamp-mpfr-h: ${CACHE}/mpfr/mpfr-3.1.2-pkg.tar.gz ${SYSROOT}/.stamp-gmp-h
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/mpc/mpc-1.0.1.tar.gz:
	mkdir -p ${CACHE}/mpc
	curl -L 'http://www.multiprecision.org/mpc/download/mpc-1.0.1.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/mpc/mpc-1.0.1-pkg.tar.gz: ${CACHE}/mpc/mpc-1.0.1.tar.gz ${CACHE}/gmp/gmp-5.1.3-pkg.tar.gz ${CACHE}/mpfr/mpfr-3.1.2-pkg.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/gmp/gmp-5.1.3-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/mpfr/mpfr-3.1.2-pkg.tar.gz
	find "${SYSROOT}" -not -type d -print0 >"${ROOT}"/.pkglist

	rm -rf "${ROOT}"/.build/mpc
	mkdir -p "${ROOT}"/.build/mpc
	tar -C "${ROOT}"/.build/mpc --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/mpc && ./configure \
	    --prefix '${SYSROOT}' \
	    --with-gmp='${SYSROOT}' \
	    --with-mpfr='${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/mpc && make all install"
	rm -rf "${ROOT}"/.build/mpc

	# Snapshot the package
	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: mpc-pkg
mpc-pkg: ${SYSROOT}/.stamp-mpc-h
${SYSROOT}/.stamp-mpc-h: ${CACHE}/mpc/mpc-1.0.1-pkg.tar.gz ${SYSROOT}/.stamp-gmp-h ${SYSROOT}/.stamp-mpfr-h
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/cityhash/cityhash-1.1.1.tar.gz:
	mkdir -p ${CACHE}/cityhash
	curl -L 'https://cityhash.googlecode.com/files/cityhash-1.1.1.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/cityhash/cityhash-1.1.1-pkg.tar.gz: ${CACHE}/cityhash/cityhash-1.1.1.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"

	rm -rf "${ROOT}"/.build/cityhash
	mkdir -p "${ROOT}"/.build/cityhash
	tar -C "${ROOT}"/.build/cityhash --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/cityhash && ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/cityhash && make all install"
	rm -rf "${ROOT}"/.build/cityhash

	# Snapshot the package
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: cityhash-pkg
cityhash-pkg: ${SYSROOT}/.stamp-cityhash-h
${SYSROOT}/.stamp-cityhash-h: ${CACHE}/cityhash/cityhash-1.1.1-pkg.tar.gz
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/sparsehash/sparsehash-2.0.2.tar.gz:
	mkdir -p "${CACHE}"/sparsehash
	curl -L 'https://sparsehash.googlecode.com/files/sparsehash-2.0.2.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/sparsehash/sparsehash-2.0.2-pkg.tar.gz: ${CACHE}/sparsehash/sparsehash-2.0.2.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"

	rm -rf "${ROOT}"/.build/sparsehash
	mkdir -p "${ROOT}"/.build/sparsehash
	tar -C "${ROOT}"/.build/sparsehash --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/sparsehash && ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/sparsehash && make all install"
	rm -rf "${ROOT}"/.build/sparsehash

	# Snapshot the package
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: sparsehash-pkg
sparsehash-pkg: ${SYSROOT}/.stamp-sparsehash-h
${SYSROOT}/.stamp-sparsehash-h: ${CACHE}/sparsehash/sparsehash-2.0.2-pkg.tar.gz
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/glog/glog-0.3.3.tar.gz:
	mkdir -p "${CACHE}"/glog
	curl -L 'https://google-glog.googlecode.com/files/glog-0.3.3.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/glog/glog-0.3.3-pkg.tar.gz: ${CACHE}/glog/glog-0.3.3.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"

	rm -rf "${ROOT}"/.build/glog
	mkdir -p "${ROOT}"/.build/glog
	tar -C "${ROOT}"/.build/glog --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/glog && ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/glog && make all install"
	rm -rf "${ROOT}"/.build/glog

	# Snapshot the package
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: glog-pkg
glog-pkg: ${SYSROOT}/.stamp-glog-h
${SYSROOT}/.stamp-glog-h: ${CACHE}/glog/glog-0.3.3-pkg.tar.gz
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/popt/popt-1.16.tar.gz:
	mkdir -p "${CACHE}"/popt
	curl -L 'http://rpm5.org/files/popt/popt-1.16.tar.gz' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/popt/popt-1.16-pkg.tar.gz: ${CACHE}/popt/popt-1.16.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"

	rm -rf "${ROOT}"/.build/popt
	mkdir -p "${ROOT}"/.build/popt
	tar -C "${ROOT}"/.build/popt --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/popt && ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/popt && make all install"
	rm -rf "${ROOT}"/.build/popt

	# Snapshot the package
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: popt-pkg
popt-pkg: ${SYSROOT}/.stamp-popt-h
${SYSROOT}/.stamp-popt-h: ${CACHE}/popt/popt-1.16-pkg.tar.gz
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3.tar.gz:
	mkdir -p "${CACHE}"/po6
	curl -L 'https://codeload.github.com/rescrv/po6/tar.gz/5c62bad959c5425579a4b63214d9fb0f50c988a3' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz: ${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"

	rm -rf "${ROOT}"/.build/po6
	mkdir -p "${ROOT}"/.build/po6
	tar -C "${ROOT}"/.build/po6 --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/po6 && autoreconf -if"
	bash -c "cd '${ROOT}'/.build/po6 && ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/po6 && make all install"
	rm -rf "${ROOT}"/.build/po6

	# Snapshot the package
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: po6-pkg
po6-pkg: ${SYSROOT}/.stamp-po6-h
${SYSROOT}/.stamp-po6-h: ${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9.tar.gz:
	mkdir -p "${CACHE}"/e
	curl -L 'https://codeload.github.com/rescrv/e/tar.gz/d51ee3dba1c9836c4674163ddde7f658d2dedec9' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz: ${CACHE}/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9.tar.gz ${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz
	find "${SYSROOT}" -not -type d -print0 >"${ROOT}"/.pkglist

	rm -rf "${ROOT}"/.build/e
	mkdir -p "${ROOT}"/.build/e
	tar -C "${ROOT}"/.build/e --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/e && autoreconf -if"
	bash -c "cd '${ROOT}'/.build/e && \
	    PKG_CONFIG_PATH='${SYSROOT}'/lib/pkgconfig ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/e && make all install"
	rm -rf "${ROOT}"/.build/e

	# Snapshot the package
	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: e-pkg
e-pkg: ${SYSROOT}/.stamp-e-h
${SYSROOT}/.stamp-e-h: ${CACHE}/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz ${SYSROOT}/.stamp-po6-h
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf.tar.gz:
	mkdir -p "${CACHE}"/busybee
	curl -L 'https://codeload.github.com/rescrv/busybee/tar.gz/29f989dfc362e412e6a0395c25ed3e53b8b05caf' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf-pkg.tar.gz: ${CACHE}/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf.tar.gz ${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz ${CACHE}/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz
	find "${SYSROOT}" -not -type d -print0 >"${ROOT}"/.pkglist

	rm -rf "${ROOT}"/.build/busybee
	mkdir -p "${ROOT}"/.build/busybee
	tar -C "${ROOT}"/.build/busybee --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/busybee && autoreconf -if"
	bash -c "cd '${ROOT}'/.build/busybee && \
	    PKG_CONFIG_PATH='${SYSROOT}'/lib/pkgconfig ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/busybee && make all install"
	rm -rf "${ROOT}"/.build/busybee

	# Snapshot the package
	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: busybee-pkg
busybee-pkg: ${SYSROOT}/.stamp-busybee-h
${SYSROOT}/.stamp-busybee-h: ${CACHE}/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf-pkg.tar.gz ${SYSROOT}/.stamp-po6-h ${SYSROOT}/.stamp-e-h
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f.tar.gz:
	mkdir -p "${CACHE}"/HyperLevelDB
	curl -L 'https://codeload.github.com/rescrv/HyperLevelDB/tar.gz/ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f-pkg.tar.gz: ${CACHE}/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"

	rm -rf "${ROOT}"/.build/HyperLevelDB
	mkdir -p "${ROOT}"/.build/HyperLevelDB
	tar -C "${ROOT}"/.build/HyperLevelDB --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/HyperLevelDB && autoreconf -if"
	if [ "x`uname -s`" = "xDarwin" ]; then\
	    CXXFLAGS=-DOS_MACOSX \
	    bash -c "cd '${ROOT}'/.build/HyperLevelDB && ./configure --prefix '${SYSROOT}'"; \
	else \
	    LDFLAGS=-lpthread \
	    bash -c "cd '${ROOT}'/.build/HyperLevelDB && ./configure --prefix '${SYSROOT}'"; \
	fi
	bash -c "cd '${ROOT}'/.build/HyperLevelDB && make all install"
	rm -rf "${ROOT}"/.build/HyperLevelDB

  # Snapshot the package
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: HyperLevelDB-pkg
HyperLevelDB-pkg: ${SYSROOT}/.stamp-HyperLevelDB-h
${SYSROOT}/.stamp-HyperLevelDB-h: ${CACHE}/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f-pkg.tar.gz
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/Replicant/Replicant-ef75f60c3a9b4adfb83c40869a516f4a879f0414.tar.gz:
	mkdir -p "${CACHE}"/Replicant
	curl -L 'https://codeload.github.com/rescrv/Replicant/tar.gz/ef75f60c3a9b4adfb83c40869a516f4a879f0414' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/Replicant/Replicant-ef75f60c3a9b4adfb83c40869a516f4a879f0414-pkg.tar.gz: ${CACHE}/Replicant/Replicant-ef75f60c3a9b4adfb83c40869a516f4a879f0414.tar.gz  ${CACHE}/glog/glog-0.3.3-pkg.tar.gz ${CACHE}/popt/popt-1.16-pkg.tar.gz ${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz ${CACHE}/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz ${CACHE}/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf-pkg.tar.gz ${CACHE}/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f-pkg.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/glog/glog-0.3.3-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/popt/popt-1.16-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f-pkg.tar.gz
	find "${SYSROOT}" -not -type d -print0 >"${ROOT}"/.pkglist

	rm -rf "${ROOT}"/.build/Replicant
	mkdir -p "${ROOT}"/.build/Replicant
	tar -C "${ROOT}"/.build/Replicant --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/Replicant && autoreconf -if"
	bash -c "cd '${ROOT}'/.build/Replicant && \
	    PKG_CONFIG_PATH='${SYSROOT}'/lib/pkgconfig CXXFLAGS=-O1 \
	    CPPFLAGS=-I'${SYSROOT}'/include LDFLAGS=-L'${SYSROOT}'/lib \
	    ./configure --prefix '${SYSROOT}'"
	bash -c "cd '${ROOT}'/.build/Replicant && make all install"
	rm -rf "${ROOT}"/.build/Replicant

	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: Replicant-pkg
Replicant-pkg: ${SYSROOT}/.stamp-Replicant-h
${SYSROOT}/.stamp-Replicant-h: ${CACHE}/Replicant/Replicant-ef75f60c3a9b4adfb83c40869a516f4a879f0414-pkg.tar.gz ${SYSROOT}/.stamp-glog-h ${SYSROOT}/.stamp-popt-h ${SYSROOT}/.stamp-po6-h ${SYSROOT}/.stamp-e-h ${SYSROOT}/.stamp-busybee-h ${SYSROOT}/.stamp-HyperLevelDB-h ${SYSROOT}/.stamp-glog-h
	tar -C "${SYSROOT}" --gzip -xf "$<"
	touch "$@"

# ===--------------------------------------------------------------------===

${CACHE}/HyperDex/HyperDex-1f301dd2cd790d2df796dd1ffe90f73867ecd33f.tar.gz:
	mkdir -p "${CACHE}"/HyperDex
	curl -L 'https://codeload.github.com/rescrv/HyperDex/tar.gz/1f301dd2cd790d2df796dd1ffe90f73867ecd33f' >'$@' || { rm -f '$@'; exit 1; }

${CACHE}/HyperDex/HyperDex-1f301dd2cd790d2df796dd1ffe90f73867ecd33f-pkg.tar.gz: ${CACHE}/HyperDex/HyperDex-1f301dd2cd790d2df796dd1ffe90f73867ecd33f.tar.gz ${PYENV}/.stamp-h ${CACHE}/cityhash/cityhash-1.1.1-pkg.tar.gz ${CACHE}/sparsehash/sparsehash-2.0.2-pkg.tar.gz ${CACHE}/glog/glog-0.3.3-pkg.tar.gz ${CACHE}/popt/popt-1.16-pkg.tar.gz ${CACHE}/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz ${CACHE}/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz ${CACHE}/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf-pkg.tar.gz ${CACHE}/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f-pkg.tar.gz ${CACHE}/Replicant/Replicant-ef75f60c3a9b4adfb83c40869a516f4a879f0414-pkg.tar.gz
	if [ -d "${SYSROOT}" ]; then \
	    mv "${SYSROOT}" "${SYSROOT}"-bak; \
	fi
	mkdir -p "${SYSROOT}"
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/cityhash/cityhash-1.1.1-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/sparsehash/sparsehash-2.0.2-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/glog/glog-0.3.3-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/popt/popt-1.16-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/po6/po6-5c62bad959c5425579a4b63214d9fb0f50c988a3-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/e/e-d51ee3dba1c9836c4674163ddde7f658d2dedec9-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/busybee/busybee-29f989dfc362e412e6a0395c25ed3e53b8b05caf-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/HyperLevelDB/HyperLevelDB-ce1cacf15c4f59cfb947b5db5dfe4e5a692eec5f-pkg.tar.gz
	tar -C "${SYSROOT}" --gzip -xf "${CACHE}"/Replicant/Replicant-ef75f60c3a9b4adfb83c40869a516f4a879f0414-pkg.tar.gz
	find "${SYSROOT}" -not -type d -print0 >"${ROOT}"/.pkglist

	rm -rf "${ROOT}"/.build/HyperDex
	mkdir -p "${ROOT}"/.build/HyperDex
	tar -C "${ROOT}"/.build/HyperDex --strip-components 1 --gzip -xf "$<"
	bash -c "cd '${ROOT}'/.build/HyperDex && autoreconf -if"
	bash -c "export PATH="${SYSROOT}/bin:$$PATH" && \
	    source '${PYENV}'/bin/activate && \
	    cd '${ROOT}'/.build/HyperDex && \
	    PKG_CONFIG_PATH='${SYSROOT}'/lib/pkgconfig \
	    CPPFLAGS=-I'${SYSROOT}'/include LDFLAGS=-L'${SYSROOT}'/lib \
	    PYTHON="${ROOT}"/.pyenv/bin/python \
	    ./configure \
	        --enable-python-bindings \
	        --prefix '${SYSROOT}'"
	bash -c "export PATH="${SYSROOT}/bin:$$PATH" && \
	    source '${PYENV}'/bin/activate && \
	    cd '${ROOT}'/.build/HyperDex && make all install"
	rm -rf "${ROOT}"/.build/HyperDex

	cat "${ROOT}"/.pkglist | xargs -0 rm -rf
	tar -C "${SYSROOT}" --gzip -cf "$@" .
	rm -rf "${SYSROOT}"
	if [ -d "${SYSROOT}"-bak ]; then \
	    mv "${SYSROOT}"-bak "${SYSROOT}"; \
	fi

.PHONY: HyperDex-pkg
HyperDex-pkg: ${SYSROOT}/.stamp-HyperDex-h
${SYSROOT}/.stamp-HyperDex-h: ${CACHE}/HyperDex/HyperDex-1f301dd2cd790d2df796dd1ffe90f73867ecd33f-pkg.tar.gz ${PYENV}/.stamp-h ${SYSROOT}/.stamp-glog-h ${SYSROOT}/.stamp-cityhash-h ${SYSROOT}/.stamp-sparsehash-h ${SYSROOT}/.stamp-popt-h ${SYSROOT}/.stamp-po6-h ${SYSROOT}/.stamp-e-h ${SYSROOT}/.stamp-busybee-h ${SYSROOT}/.stamp-HyperLevelDB-h ${SYSROOT}/.stamp-Replicant-h
	tar -C "${SYSROOT}" --gzip -xf "$<"
	$(MAKE) HyperDex-python-bindings
	touch "$@"
