%{!?_initrddir:%define _initrddir /etc/rc.d/init.d}
%{!?version:%define version 1.7}
%{!?release:%define release 1}

Summary: Freeside ISP Billing System
Name: freeside
Version: %{version}
Release: %{release}
License: AGPL
Group: Applications/Internet
URL: http://www.sisd.com/freeside/
Packager: Richard Siddall <richard.siddall@elirion.net>
Vendor: Freeside
Source: http://www.sisd.com/freeside/%{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch
Requires: %{name}-frontend
Requires: %{name}-backend
Requires: tetex-latex
Requires: perl-Fax-Hylafax-Client

%define freeside_document_root	/var/www/freeside
%define freeside_cache		/var/cache/subsys/freeside
%define freeside_conf		/etc/freeside
%define freeside_export		/etc/freeside
%define freeside_lock		/var/lock/freeside
%define freeside_log		/var/log/freeside
%define	rt_enabled		0
%define apache_conffile		/etc/httpd/conf/httpd.conf
%define	apache_confdir		/etc/httpd/conf.d
%define	apache_version		2
%define	fs_queue_user		fs_queue
%define	fs_selfservice_user	fs_selfservice
%define	fs_cron_user		fs_daily

%define _rpmlibdir	/usr/lib/rpm

%description
Freeside is a flexible ISP billing system written by Ivan Kohler

%package mason
Summary: HTML::Mason interface for %{name}
Group: Applications/Internet
Prefix: /var/www/freeside
Requires: mod_ssl
Requires: perl-Apache-DBI
%%include freeside-mason.deps.inc
Conflicts: %{name}-apacheasp
Provides: %{name}-frontend
BuildArch: noarch

%description mason
This package includes the HTML::Mason web interface for %{name}.
You should install only one %{name} web interface.

%package postgresql
Summary: PostgreSQL backend for %{name}
Group: Applications/Internet
Requires: perl-DBI
Requires: perl-DBD-Pg >= 1.32
Requires: %{name}
Conflicts: %{name}-mysql
Provides: %{name}-backend

%description postgresql
This package includes the PostgreSQL database backend for %{name}.
You should install only one %{name} database backend.
Please note that this RPM does not create the database or database user; it only installs the required drivers.

%package mysql
Summary: MySQL database backend for %{name}
Group: Applications/Internet
Requires: perl-DBI
Requires: perl-DBD-MySQL
Requires: %{name}
Conflicts: %{name}-postgresql
Provides: %{name}-backend

%description mysql
This package includes the MySQL database backend for %{name}.
You should install only one %{name} database backend.
Please note that this RPM does not create the database or database user; it only installs the required drivers.

%package selfservice
Summary: Self-service interface for %{name}
Group: Applications/Internet
Conflicts: %{name}

%description selfservice
This package installs the Perl modules and CGI scripts for the self-service interface for %{name}.
For security reasons, it is set to conflict with %{name} so you cannot install the billing system and self-service interface on the same computer.

%prep
%setup
%{__rm} bin/pod2x # Only useful to Ivan Kohler now
%{__cp} install/rpm/freeside-install FS/bin
perl -pi -e 's|/usr/local/bin|%{buildroot}%{_bindir}|g' FS/Makefile.PL
perl -ni -e 'print if !/\s+chown\s+/;' Makefile

%build

# Add freeside user and group if there isn't already such a user
%{__id} freeside 2>/dev/null >/dev/null || /usr/sbin/useradd -s /bin/sh freeside
# False laziness...
# The htmlman target now makes wiki documentation.  Let's pretend we made it.
touch htmlman
%{__make} alldocs

#perl -pi -e 's|%%%%%%VERSION%%%%%%|%{version}|g' FS/bin/*
cd FS
CFLAGS="$RPM_OPT_FLAGS" perl Makefile.PL PREFIX=$RPM_BUILD_ROOT%{_prefix} SITELIBEXP=$RPM_BUILD_ROOT%{perl_sitelib} SITEARCHEXP=$RPM_BUILD_ROOT%{perl_sitearch}
%{__make} OPTIMIZE="$RPM_OPT_FLAGS"
cd ..
%{__make} perl-modules FREESIDE_CACHE=%{freeside_cache} FREESIDE_CONF=%{freeside_conf} FREESIDE_EXPORT=%{freeside_export} FREESIDE_LOCK=%{freeside_lock} FREESIDE_LOG=%{freeside_log}
touch perl-modules

cd fs_selfservice/FS-SelfService
CFLAGS="$RPM_OPT_FLAGS" perl Makefile.PL PREFIX=$RPM_BUILD_ROOT%{_prefix} SITELIBEXP=$RPM_BUILD_ROOT%{perl_sitelib} SITEARCHEXP=$RPM_BUILD_ROOT%{perl_sitearch} INSTALLSCRIPT=$RPM_BUILD_ROOT%{_sbindir}
%{__make} OPTIMIZE="$RPM_OPT_FLAGS"
cd ../..

%install
%{__rm} -rf %{buildroot}

%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_document_root}

touch install-perl-modules perl-modules
%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_cache}
%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_conf}
#%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_export}
%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_lock}
%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_log}
%{__make} create-config RT_ENABLED=%{rt_enabled} FREESIDE_CACHE=$RPM_BUILD_ROOT%{freeside_cache} FREESIDE_CONF=$RPM_BUILD_ROOT%{freeside_conf} FREESIDE_EXPORT=$RPM_BUILD_ROOT%{freeside_export} FREESIDE_LOCK=$RPM_BUILD_ROOT%{freeside_lock} FREESIDE_LOG=$RPM_BUILD_ROOT%{freeside_log}
%{__rm} install-perl-modules perl-modules $RPM_BUILD_ROOT%{freeside_conf}/conf*/ticket_system

touch docs
%{__perl} -pi -e "s|%%%%%%FREESIDE_DOCUMENT_ROOT%%%%%%|%{freeside_document_root}|g" htetc/handler.pl
%{__make} install-docs RT_ENABLED=%{rt_enabled} PREFIX=$RPM_BUILD_ROOT%{_prefix} TEMPLATE=mason FREESIDE_DOCUMENT_ROOT=$RPM_BUILD_ROOT%{freeside_document_root} MASON_HANDLER=$RPM_BUILD_ROOT%{freeside_conf}/handler.pl MASONDATA=$RPM_BUILD_ROOT%{freeside_cache}/masondata
%{__perl} -pi -e "s|$RPM_BUILD_ROOT||g" $RPM_BUILD_ROOT%{freeside_conf}/handler.pl
%{__rm} docs

# Install the init script
%{__mkdir_p} $RPM_BUILD_ROOT%{_initrddir}
%{__install} init.d/freeside-init $RPM_BUILD_ROOT%{_initrddir}/%{name}
#%{__make} install-init INSTALLGROUP=root INIT_FILE=$RPM_BUILD_ROOT%{_initrddir}/%{name}
%{__perl} -pi -e "\
	  s/%%%%%%QUEUED_USER%%%%%%/%{fs_queue_user}/g;\
	  s/%%%%%%SELFSERVICE_USER%%%%%%/%{fs_selfservice_user}/g;\
	  s/%%%%%%SELFSERVICE_MACHINES%%%%%%//g;\
	" $RPM_BUILD_ROOT%{_initrddir}/%{name}

# Install the HTTPD configuration snippet for HTML::Mason
%{__mkdir_p} $RPM_BUILD_ROOT%{apache_confdir}
%{__make} install-apache FREESIDE_DOCUMENT_ROOT=%{freeside_document_root} RT_ENABLED=%{rt_enabled} APACHE_CONF=$RPM_BUILD_ROOT%{apache_confdir} APACHE_VERSION=%{apache_version} MASON_HANDLER=%{freeside_conf}/handler.pl
%{__perl} -pi -e "s|%%%%%%FREESIDE_DOCUMENT_ROOT%%%%%%|%{freeside_document_root}|g" $RPM_BUILD_ROOT%{apache_confdir}/freeside-*.conf
%{__perl} -pi -e "s|%%%%%%MASON_HANDLER%%%%%%|%{freeside_conf}/handler.pl|g" $RPM_BUILD_ROOT%{apache_confdir}/freeside-*.conf
%{__perl} -pi -e "s|/usr/local/etc/freeside|%{freeside_conf}|g" $RPM_BUILD_ROOT%{apache_confdir}/freeside-*.conf
%{__perl} -pi -e 'print "Alias /%{name} %{freeside_document_root}\n\n" if /^<Directory/;' $RPM_BUILD_ROOT%{apache_confdir}/freeside-*.conf
%{__perl} -pi -e 'print "SSLRequireSSL\n" if /^AuthName/i;' $RPM_BUILD_ROOT%{apache_confdir}/freeside-*.conf

# Make a list of the Mason files before adding self-service, etc.
find $RPM_BUILD_ROOT%{freeside_document_root} -type f -print | \
        sed "s@^$RPM_BUILD_ROOT@@g" > %{name}-%{version}-%{release}-mason-filelist
if [ "$(cat %{name}-%{version}-%{release}-mason-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi

# Install all the miscellaneous binaries into /usr/share or similar
%{__mkdir_p} $RPM_BUILD_ROOT%{_datadir}/%{name}-%{version}
%{__install} bin/* $RPM_BUILD_ROOT%{_datadir}/%{name}-%{version}

%{__mkdir_p} $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig
%{__install} install/rpm/freeside.sysconfig $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/%{name}

%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_document_root}/selfservice
%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_document_root}/selfservice/cgi
%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_document_root}/selfservice/php
%{__mkdir_p} $RPM_BUILD_ROOT%{freeside_document_root}/selfservice/templates
%{__install} fs_selfservice/FS-SelfService/cgi/* $RPM_BUILD_ROOT%{freeside_document_root}/selfservice/cgi
%{__install} fs_selfservice/php/* $RPM_BUILD_ROOT%{freeside_document_root}/selfservice/php
%{__install} fs_selfservice/FS-SelfService/*.template $RPM_BUILD_ROOT%{freeside_document_root}/selfservice/templates

# Install the main billing server Perl files
cd FS
eval `perl '-V:installarchlib'`
%{__mkdir_p} $RPM_BUILD_ROOT$installarchlib
%makeinstall PREFIX=$RPM_BUILD_ROOT%{_prefix}
%{__rm} -f `find $RPM_BUILD_ROOT -type f -name perllocal.pod -o -name .packlist`

[ -x %{_rpmlibdir}/brp-compress ] && %{_rpmlibdir}/brp-compress

find $RPM_BUILD_ROOT%{_prefix} -type f -print | \
	grep -v '/etc/freeside/conf' | \
	grep -v '/etc/freeside/secrets' | \
        sed "s@^$RPM_BUILD_ROOT@@g" > %{name}-%{version}-%{release}-filelist
if [ "$(cat %{name}-%{version}-%{release}-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi
cd ..

# Install the self-service interface Perl files
cd fs_selfservice/FS-SelfService
%{__mkdir_p} $RPM_BUILD_ROOT%{_prefix}/local/bin
%makeinstall PREFIX=$RPM_BUILD_ROOT%{_prefix}
%{__rm} -f `find $RPM_BUILD_ROOT -type f -name perllocal.pod -o -name .packlist`

[ -x %{_rpmlibdir}/brp-compress ] && %{_rpmlibdir}/brp-compress

find $RPM_BUILD_ROOT%{_prefix} -type f -print | \
	grep -v '/etc/freeside/conf' | \
	grep -v '/etc/freeside/secrets' | \
        sed "s@^$RPM_BUILD_ROOT@@g" > %{name}-%{version}-%{release}-temp-filelist
cat ../../FS/%{name}-%{version}-%{release}-filelist %{name}-%{version}-%{release}-temp-filelist | sort | uniq -u >  %{name}-%{version}-%{release}-selfservice-filelist
if [ "$(cat %{name}-%{version}-%{release}-selfservice-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi
cd ../..

%pre
if ! %{__id} freeside &>/dev/null; then
	/usr/sbin/useradd freeside
fi

%pre mason
if ! %{__id} freeside &>/dev/null; then
	/usr/sbin/useradd freeside
fi

%pre selfservice
if ! %{__id} freeside &>/dev/null; then
	/usr/sbin/useradd freeside
fi

%post
if [ -x /sbin/chkconfig ]; then
	/sbin/chkconfig --add freeside
fi
#if [ $1 -eq 2 -a -x /usr/bin/freeside-upgrade ]; then
#fi

%post mason
# Make local httpd run with User/Group = freeside
if [ -f %{apache_conffile} ]; then
	perl -p -i.fsbackup -e 's/^(User|Group) .*/$1 freeside/' %{apache_conffile}
fi

%clean
%{__rm} -rf %{buildroot}

%files -f FS/%{name}-%{version}-%{release}-filelist
%attr(0711,root,root) %{_initrddir}/%{name}
%attr(0644,root,root) %config(noreplace) %{_sysconfdir}/sysconfig/%{name}
%defattr(-,freeside,freeside,-)
%doc README INSTALL CREDITS AGPL
%attr(-,freeside,freeside) %config(noreplace) %{freeside_conf}/conf.*
%attr(-,freeside,freeside) %config(noreplace) %{freeside_cache}/counters.*
%attr(-,freeside,freeside) %config(noreplace) %{freeside_cache}/cache.*
%attr(-,freeside,freeside) %config(noreplace) %{freeside_export}/export.*
%attr(-,freeside,freeside) %config(noreplace) %{freeside_conf}/secrets
%attr(-,freeside,freeside) %dir %{freeside_conf}
%attr(-,freeside,freeside) %dir %{freeside_lock}
%attr(-,freeside,freeside) %dir %{freeside_log}

%files mason -f %{name}-%{version}-%{release}-mason-filelist
%defattr(-, freeside, freeside, 0755)
%attr(-,freeside,freeside) %{freeside_conf}/handler.pl
%attr(-,freeside,freeside) %{freeside_cache}/masondata
%attr(0644,root,root) %config(noreplace) %{apache_confdir}/%{name}-base%{apache_version}.conf

%files postgresql

%files mysql

%files selfservice -f fs_selfservice/FS-SelfService/%{name}-%{version}-%{release}-selfservice-filelist
%defattr(-, freeside, freeside, 0644)
%attr(0755,freeside,freeside) %{freeside_document_root}/selfservice/cgi
%attr(0755,freeside,freeside) %{freeside_document_root}/selfservice/php
%attr(0644,freeside,freeside) %{freeside_document_root}/selfservice/templates

%changelog
* Sun Jul 8 2007 Richard Siddall <richard.siddall@elirion.net> - 1.7.3
- Updated for upcoming Freeside 1.7.3
- RT support is still missing

* Fri Jun 29 2007 Richard Siddall <richard.siddall@elirion.net> - 1.7.2
- Updated for Freeside 1.7.2
- Removed support for Apache::ASP

* Wed Oct 12 2005 Richard Siddall <richard.siddall@elirion.net> - 1.5.7
- Added self-service package

* Sun Feb 06 2005 Richard Siddall <richard.siddall@elirion.net> - 1.5.0pre6-1
- Initial package
