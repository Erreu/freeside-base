%{!?_initrddir:%define _initrddir /etc/rc.d/init.d}

Summary: Freeside ISP Billing System
Name: freeside
Version: 1.5.7
Release: 3
License: GPL
Group: Applications/Internet
URL: http://www.sisd.com/freeside/
Packager: Richard Siddall <richard.siddall@elirion.net>
Vendor: Freeside
Source: http://www.sisd.com/freeside/%{name}-%{version}.tar.gz
Source1: freeside-mason.conf
Source2: freeside-asp.conf
Source3: freeside-install
Source4: freeside-import
Source5: freeside.sysconfig
Patch: %{name}-%{version}.build.patch
Patch1: %{name}-%{version}.dbd-pg.patch
Patch2: %{name}-%{version}.mod_perl2.patch
Patch3: %{name}-%{version}.redhat.patch
Patch4: %{name}-%{version}.rpm.patch
Patch5: %{name}-%{version}.emailsubject.patch
Patch6: %{name}-%{version}.nasport.patch
Patch7: %{name}-%{version}.flat_prorate.patch
Patch8: %{name}-%{version}.typo.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch
Requires: %{name}-frontend
Requires: %{name}-backend
Requires: tetex-latex
%{?fc1:BuildRequires: httpd}
%{?el3:BuildRequires: httpd}
%{?rh9:BuildRequires: httpd}
%{?rh8:BuildRequires: httpd}
%{?rh7:BuildRequires: apache}
%{?el2:BuildRequires: apache}
%{?rh6:BuildRequires: apache}

%description
Freeside is a flexible ISP billing system written by Ivan Kohler

%package mason
Summary: HTML::Mason interface for %{name}
Group: Applications/Internet
Prefix: /var/www/freeside
Requires: mod_ssl
Requires: perl(HTML::Mason)
Requires: perl(HTML::Mason::ApacheHandler)
Requires: perl(CGI)
Requires: perl(Date::Format)
Requires: perl(Date::Parse)
Requires: perl(Time::Local)
Requires: perl(Time::Duration)
Requires: perl(Tie::IxHash)
Requires: perl(URI::Escape)
Requires: perl(HTML::Entities)
Requires: perl(IO::Handle)
Requires: perl(IO::File)
Requires: perl(IO::Scalar)
Requires: perl(Net::Whois::Raw)
Requires: perl(Text::CSV_XS)
Requires: perl(Spreadsheet::WriteExcel)
Requires: perl(Business::CreditCard)
Requires: perl(String::Approx)
Requires: perl(Chart::LinesPoints)
Requires: perl(HTML::Widgets::SelectLayers)
Requires: perl(FS)
Requires: perl(FS::UID)
Requires: perl(FS::Record)
Requires: perl(FS::Conf)
Requires: perl(FS::CGI)
Requires: perl(FS::UI::Web)
Requires: perl(FS::Msgcat)
Requires: perl(FS::Misc)
Requires: perl(FS::Report::Table::Monthly)
Requires: perl(FS::TicketSystem)
Requires: perl(FS::agent)
Requires: perl(FS::agent_type)
Requires: perl(FS::domain_record)
Requires: perl(FS::cust_bill)
Requires: perl(FS::cust_bill_pay)
Requires: perl(FS::cust_credit)
Requires: perl(FS::cust_credit_bill)
Requires: perl(FS::cust_main)
Requires: perl(FS::cust_main_county)
Requires: perl(FS::cust_pay)
Requires: perl(FS::cust_pkg)
Requires: perl(FS::cust_refund)
Requires: perl(FS::cust_svc)
Requires: perl(FS::nas)
Requires: perl(FS::part_bill_event)
Requires: perl(FS::part_pkg)
Requires: perl(FS::part_referral)
Requires: perl(FS::part_svc)
Requires: perl(FS::part_svc_router)
Requires: perl(FS::part_virtual_field)
Requires: perl(FS::pkg_svc)
Requires: perl(FS::port)
Requires: perl(FS::queue)
Requires: perl(FS::raddb)
Requires: perl(FS::session)
Requires: perl(FS::svc_acct)
Requires: perl(FS::svc_acct_pop)
Requires: perl(FS::svc_domain)
Requires: perl(FS::svc_forward)
Requires: perl(FS::svc_www)
Requires: perl(FS::router)
Requires: perl(FS::addr_block)
Requires: perl(FS::svc_broadband)
Requires: perl(FS::svc_external)
Requires: perl(FS::type_pkgs)
Requires: perl(FS::part_export)
Requires: perl(FS::part_export_option)
Requires: perl(FS::export_svc)
Requires: perl(FS::msgcat)
Requires: perl(FS::rate)
Requires: perl(FS::rate_region)
Requires: perl(FS::rate_prefix)
Requires: perl(FS::XMLRPC)
Requires: perl(MIME::Entity)
Requires: perl(Text::Wrapper)
Requires: perl(CGI::Cookie)
Requires: perl(Time::ParseDate)
Requires: perl(HTML::Scrubber)
Requires: perl(Text::Quoted)
Conflicts: %{name}-apacheasp
Provides: %{name}-frontend
BuildArch: noarch

%description mason
This package includes the HTML::Mason web interface for %{name}.
You should install only one %{name} web interface.

%package apacheasp
Summary: Apache::ASP interface for %{name}
Group: Applications/Internet
Prefix: /var/www/freeside
Requires: mod_ssl
Requires: perl(Apache::ASP)
Requires: perl(CGI)
Requires: perl(Date::Format)
Requires: perl(Date::Parse)
Requires: perl(Time::Local)
Requires: perl(Time::Duration)
Requires: perl(Tie::IxHash)
Requires: perl(URI::Escape)
Requires: perl(HTML::Entities)
Requires: perl(IO::Handle)
Requires: perl(IO::File)
Requires: perl(IO::Scalar)
Requires: perl(Net::Whois::Raw)
Requires: perl(Text::CSV_XS)
Requires: perl(Spreadsheet::WriteExcel)
Requires: perl(Business::CreditCard)
Requires: perl(String::Approx)
Requires: perl(Chart::LinesPoints)
Requires: perl(HTML::Widgets::SelectLayers)
Requires: perl(FS)
Requires: perl(FS::UID)
Requires: perl(FS::Record)
Requires: perl(FS::Conf)
Requires: perl(FS::CGI)
Requires: perl(FS::UI::Web)
Requires: perl(FS::Msgcat)
Requires: perl(FS::Misc)
Requires: perl(FS::Report::Table::Monthly)
Requires: perl(FS::TicketSystem)
Requires: perl(FS::agent)
Requires: perl(FS::agent_type)
Requires: perl(FS::domain_record)
Requires: perl(FS::cust_bill)
Requires: perl(FS::cust_bill_pay)
Requires: perl(FS::cust_credit)
Requires: perl(FS::cust_credit_bill)
Requires: perl(FS::cust_main)
Requires: perl(FS::cust_main_county)
Requires: perl(FS::cust_pay)
Requires: perl(FS::cust_pkg)
Requires: perl(FS::cust_refund)
Requires: perl(FS::cust_svc)
Requires: perl(FS::nas)
Requires: perl(FS::part_bill_event)
Requires: perl(FS::part_pkg)
Requires: perl(FS::part_referral)
Requires: perl(FS::part_svc)
Requires: perl(FS::part_svc_router)
Requires: perl(FS::part_virtual_field)
Requires: perl(FS::pkg_svc)
Requires: perl(FS::port)
Requires: perl(FS::queue)
Requires: perl(FS::raddb)
Requires: perl(FS::session)
Requires: perl(FS::svc_acct)
Requires: perl(FS::svc_acct_pop)
Requires: perl(FS::svc_domain)
Requires: perl(FS::svc_forward)
Requires: perl(FS::svc_www)
Requires: perl(FS::router)
Requires: perl(FS::addr_block)
Requires: perl(FS::svc_broadband)
Requires: perl(FS::svc_external)
Requires: perl(FS::type_pkgs)
Requires: perl(FS::part_export)
Requires: perl(FS::part_export_option)
Requires: perl(FS::export_svc)
Requires: perl(FS::msgcat)
Requires: perl(FS::rate)
Requires: perl(FS::rate_region)
Requires: perl(FS::rate_prefix)
Requires: perl(Data::Dumper)
Conflicts: %{name}-mason
Provides: %{name}-frontend
BuildArch: noarch

%description apacheasp
This package includes the Apache::ASP web interface for %{name}.
You should install only one %{name} web interface.
Please note that this interface is deprecated as future versions of %{name} will use
the HTML::Mason-based RT tracking tool.

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
%patch0 -p1
%patch1 -p1
%patch2 -p1
%patch3 -p1
%patch4 -p1
%patch5 -p1
%patch6 -p1
%patch7 -p1
%patch8 -p1
%{__cp} %SOURCE3 FS/bin
%{__cp} %SOURCE4 FS/bin
#%{__rm} -r FS/FS/UI/Gtk.pm
perl -pi -e 's|/usr/local/bin|%{buildroot}%{_bindir}|g' FS/Makefile.PL
perl -ni -e 'print if !/\s+chown\s+/;' Makefile

%build
# Add freeside user and group if there isn't already such a user
%{__id} freeside 2>/dev/null >/dev/null || /usr/sbin/useradd -s /bin/sh -r freeside
# False laziness...
%{__make} htmlman
echo "Made HTML manuals"
touch htmlman
%{__make} alldocs

cd FS
CFLAGS="$RPM_OPT_FLAGS" perl Makefile.PL PREFIX=$RPM_BUILD_ROOT%{_prefix} SITELIBEXP=$RPM_BUILD_ROOT%{perl_sitelib} SITEARCHEXP=$RPM_BUILD_ROOT%{perl_sitearch}
%{__make} OPTIMIZE="$RPM_OPT_FLAGS"
cd ..

cd fs_selfservice/FS-SelfService
CFLAGS="$RPM_OPT_FLAGS" perl Makefile.PL PREFIX=$RPM_BUILD_ROOT%{_prefix} SITELIBEXP=$RPM_BUILD_ROOT%{perl_sitelib} SITEARCHEXP=$RPM_BUILD_ROOT%{perl_sitearch}
%{__make} OPTIMIZE="$RPM_OPT_FLAGS"
cd ../..

%install
%{__rm} -rf %{buildroot}

FREESIDE_DOCUMENT_ROOT=/var/www/freeside
%{__mkdir_p} $RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/asp
%{__mkdir_p} $RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/mason

touch install-perl-modules perl-modules
%{__make} create-config FREESIDE_CONF=$RPM_BUILD_ROOT/usr/local/etc/freeside
%{__rm} install-perl-modules perl-modules

touch docs
%{__perl} -pi -e "s|%%%%%%FREESIDE_DOCUMENT_ROOT%%%%%%|$FREESIDE_DOCUMENT_ROOT/asp|g" htetc/global.asa
%{__perl} -pi -e "s|%%%%%%FREESIDE_DOCUMENT_ROOT%%%%%%|$FREESIDE_DOCUMENT_ROOT/mason|g" htetc/handler.pl
%{__make} install-docs PREFIX=$RPM_BUILD_ROOT%{_prefix} TEMPLATE=asp FREESIDE_DOCUMENT_ROOT=$RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/asp ASP_GLOBAL=$RPM_BUILD_ROOT/usr/local/etc/freeside/asp-global
%{__make} install-docs PREFIX=$RPM_BUILD_ROOT%{_prefix} TEMPLATE=mason FREESIDE_DOCUMENT_ROOT=$RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/mason MASON_HANDLER=$RPM_BUILD_ROOT/usr/local/etc/freeside/handler.pl MASONDATA=$RPM_BUILD_ROOT/usr/local/etc/freeside/masondata
%{__rm} docs

# Install the init script
%{__mkdir_p} $RPM_BUILD_ROOT%{_initrddir}
%{__install} init.d/freeside-init $RPM_BUILD_ROOT%{_initrddir}/freeside

# Install the HTTPD configuration snippets for HTML::Mason and Apache::ASP
%{__mkdir_p} $RPM_BUILD_ROOT/etc/httpd/conf.d
%{__install} %SOURCE1 $RPM_BUILD_ROOT/etc/httpd/conf.d
%{__install} %SOURCE2 $RPM_BUILD_ROOT/etc/httpd/conf.d

# Install all the miscellaneous binaries into /usr/share or similar
%{__mkdir_p} $RPM_BUILD_ROOT%{_datadir}/%{name}-%{version}
%{__install} bin/* $RPM_BUILD_ROOT%{_datadir}/%{name}-%{version}

#%{__mkdir_p} $RPM_BUILD_ROOT%{_bindir}
#%{__install} %SOURCE3 $RPM_BUILD_ROOT%{_bindir}
#%{__install} %SOURCE4 $RPM_BUILD_ROOT%{_bindir}

%{__mkdir_p} $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig
%{__install} %SOURCE5 $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/%{name}

%{__mkdir_p} $RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/selfservice
%{__mkdir_p} $RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/selfservice/cgi
%{__mkdir_p} $RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/selfservice/templates
%{__install} fs_selfservice/FS-SelfService/cgi/* $RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/selfservice/cgi
%{__install} fs_selfservice/FS-SelfService/*.template $RPM_BUILD_ROOT$FREESIDE_DOCUMENT_ROOT/selfservice/templates

# Install the main billing server Perl files
cd FS
eval `perl '-V:installarchlib'`
%{__mkdir_p} $RPM_BUILD_ROOT$installarchlib
%makeinstall PREFIX=$RPM_BUILD_ROOT%{_prefix}
%{__rm} -f `find $RPM_BUILD_ROOT -type f -name perllocal.pod -o -name .packlist`

[ -x %{_libdir}/rpm/brp-compress ] && %{_libdir}/rpm/brp-compress

find $RPM_BUILD_ROOT%{_prefix} -type f -print | \
	grep -v '/usr/local/etc/freeside/conf' | \
	grep -v '/usr/local/etc/freeside/secrets' | \
        sed "s@^$RPM_BUILD_ROOT@@g" > %{name}-%{version}-%{release}-filelist
if [ "$(cat %{name}-%{version}-%{release}-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi
cd ..

# Install the self-service interface Perl files
cd fs_selfservice/FS-SelfService
eval `perl '-V:installarchlib'`
%{__mkdir_p} $RPM_BUILD_ROOT/tmp
%{__mkdir_p} $RPM_BUILD_ROOT/tmp/$installarchlib
%makeinstall PREFIX=$RPM_BUILD_ROOT/tmp%{_prefix} INSTALLSCRIPT=$RPM_BUILD_ROOT/tmp%{_prefix}/local/bin
%{__rm} -f `find $RPM_BUILD_ROOT -type f -name perllocal.pod -o -name .packlist`

[ -x %{_libdir}/rpm/brp-compress ] && (export RPM_BUILD_ROOT=$RPM_BUILD_ROOT/tmp; %{_libdir}/rpm/brp-compress)

find $RPM_BUILD_ROOT/tmp%{_prefix} -type f -print | \
        sed "s@^$RPM_BUILD_ROOT/tmp@@g" > %{name}-%{version}-%{release}-selfservice-filelist
if [ "$(cat %{name}-%{version}-%{release}-selfservice-filelist)X" = "X" ] ; then
    echo "ERROR: EMPTY FILE LIST"
    exit 1
fi
# Got the file list, now remove the temporary installation and re-install
%{__rm} -r $RPM_BUILD_ROOT/tmp
%{__mkdir_p} $RPM_BUILD_ROOT%{_prefix}/local/bin
%makeinstall PREFIX=$RPM_BUILD_ROOT%{_prefix} INSTALLSCRIPT=$RPM_BUILD_ROOT%{_prefix}/local/bin
%{__rm} -f `find $RPM_BUILD_ROOT -type f -name perllocal.pod -o -name .packlist`

[ -x %{_libdir}/rpm/brp-compress ] && %{_libdir}/rpm/brp-compress
cd ../..

%pre
if ! %{__id} freeside &>/dev/null; then
	/usr/sbin/useradd -r freeside
fi

%pre selfservice
if ! %{__id} freeside &>/dev/null; then
	/usr/sbin/useradd -r freeside
fi

%clean
%{__rm} -rf %{buildroot}

%files -f FS/%{name}-%{version}-%{release}-filelist
/etc/rc.d/init.d/freeside
%attr(0644,root,root) %config(noreplace) /etc/sysconfig/freeside
%defattr(-,freeside,freeside,-)
%doc README INSTALL CREDITS GPL
%attr(-,freeside,freeside) %config(noreplace) /usr/local/etc/freeside/conf.*
%attr(-,freeside,freeside) %config(noreplace) /usr/local/etc/freeside/counters.*
%attr(-,freeside,freeside) %config(noreplace) /usr/local/etc/freeside/cache.*
%attr(-,freeside,freeside) %config(noreplace) /usr/local/etc/freeside/export.*
%attr(-,freeside,freeside) %config(noreplace) /usr/local/etc/freeside/secrets
%attr(-,freeside,freeside) %dir /usr/local/etc/freeside

%files apacheasp
%defattr(-, freeside, freeside, 0755)
%attr(0755,freeside,freeside) /var/www/freeside/asp
%attr(-,freeside,freeside) /usr/local/etc/freeside/asp-global
%attr(0644,root,root) /etc/httpd/conf.d/freeside-asp.conf

%files mason
%defattr(-, freeside, freeside, 0755)
%attr(0755,freeside,freeside) /var/www/freeside/mason
%attr(-,freeside,freeside) /usr/local/etc/freeside/handler.pl
%attr(-,freeside,freeside) /usr/local/etc/freeside/masondata
%attr(0644,root,root) /etc/httpd/conf.d/freeside-mason.conf

%files postgresql

%files mysql

%files selfservice -f fs_selfservice/FS-SelfService/%{name}-%{version}-%{release}-selfservice-filelist
%defattr(-, freeside, freeside, 0644)
%attr(0755,freeside,freeside) /var/www/freeside/selfservice/cgi
%attr(0644,freeside,freeside) /var/www/freeside/selfservice/templates

%changelog
* Wed Oct 12 2005 Richard Siddall <richard.siddall@elirion.net> - 1.5.7
- Added self-service package

* Sun Feb 06 2005 Richard Siddall <richard.siddall@elirion.net> - 1.5.0pre6-1
- Initial package
