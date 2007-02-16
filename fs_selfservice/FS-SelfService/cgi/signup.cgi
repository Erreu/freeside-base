#!/usr/bin/perl -T
#!/usr/bin/perl -Tw

use strict;
use vars qw( @payby $cgi $init_data
             $self_url $error $agentnum

             $ieak_file $ieak_template
             $signup_html $signup_template
             $success_html $success_template
             $decline_html $decline_template
           );

use subs qw( print_form print_okay print_decline
             success_default decline_default
           );
use CGI;
#use CGI::Carp qw(fatalsToBrowser);
use Text::Template;
use Business::CreditCard;
use HTTP::BrowserDetect;
use FS::SelfService qw( signup_info new_customer );

#acceptable payment methods
#
#@payby = qw( CARD BILL COMP );
#@payby = qw( CARD BILL );
#@payby = qw( CARD );
@payby = qw( CARD PREPAY );

$ieak_file = '/usr/local/freeside/ieak.template';
$signup_html = -e 'signup.html'
                 ? 'signup.html'
                 : '/usr/local/freeside/signup.html';
$success_html = -e 'success.html'
                  ? 'success.html'
                  : '/usr/local/freeside/success.html';
$decline_html = -e 'decline.html'
                  ? 'decline.html'
                  : '/usr/local/freeside/decline.html';


if ( -e $ieak_file ) {
  my $ieak_txt = Text::Template::_load_text($ieak_file)
    or die $Text::Template::ERROR;
  $ieak_txt =~ /^(.*)$/s; #untaint the template source - it's trusted
  $ieak_txt = $1;
  $ieak_txt =~ s/\r//g; # don't double \r on old templates
  $ieak_txt =~ s/\n/\r\n/g;
  $ieak_template = new Text::Template ( TYPE => 'STRING', SOURCE => $ieak_txt )
    or die $Text::Template::ERROR;
} else {
  $ieak_template = '';
}

$agentnum = '';
if ( -e $signup_html ) {
  my $signup_txt = Text::Template::_load_text($signup_html)
    or die $Text::Template::ERROR;
  $signup_txt =~ /^(.*)$/s; #untaint the template source - it's trusted
  $signup_txt = $1;
  $signup_template = new Text::Template ( TYPE => 'STRING',
                                          SOURCE => $signup_txt,
                                          DELIMITERS => [ '<%=', '%>' ]
                                        )
    or die $Text::Template::ERROR;
  if ( $signup_txt =~
         /<\s*INPUT TYPE="?hidden"?\s+NAME="?agentnum"?\s+VALUE="?(\d+)"?\s*>/si
  ) {
    $agentnum = $1;
  }
} else {
  #too much maintenance hassle to keep in this file
  die "can't find ./signup.html or /usr/local/freeside/signup.html";
  #$signup_template = new Text::Template ( TYPE => 'STRING',
  #                                        SOURCE => &signup_default,
  #                                        DELIMITERS => [ '<%=', '%>' ]
  #                                      )
  #  or die $Text::Template::ERROR;
}

if ( -e $success_html ) {
  my $success_txt = Text::Template::_load_text($success_html)
    or die $Text::Template::ERROR;
  $success_txt =~ /^(.*)$/s; #untaint the template source - it's trusted
  $success_txt = $1;
  $success_template = new Text::Template ( TYPE => 'STRING',
                                           SOURCE => $success_txt,
                                           DELIMITERS => [ '<%=', '%>' ],
                                         )
    or die $Text::Template::ERROR;
} else {
  $success_template = new Text::Template ( TYPE => 'STRING',
                                           SOURCE => &success_default,
                                           DELIMITERS => [ '<%=', '%>' ],
                                         )
    or die $Text::Template::ERROR;
}

if ( -e $decline_html ) {
  my $decline_txt = Text::Template::_load_text($decline_html)
    or die $Text::Template::ERROR;
  $decline_txt =~ /^(.*)$/s; #untaint the template source - it's trusted
  $decline_txt = $1;
  $decline_template = new Text::Template ( TYPE => 'STRING',
                                           SOURCE => $decline_txt,
                                           DELIMITERS => [ '<%=', '%>' ],
                                         )
    or die $Text::Template::ERROR;
} else {
  $decline_template = new Text::Template ( TYPE => 'STRING',
                                           SOURCE => &decline_default,
                                           DELIMITERS => [ '<%=', '%>' ],
                                         )
    or die $Text::Template::ERROR;
}

$cgi = new CGI;

$init_data = signup_info( 'agentnum'   => $agentnum,
                          'promo_code' => scalar($cgi->param('promo_code')),
                          'reg_code'   => uc(scalar($cgi->param('reg_code'))),
                        );

if (    ( defined($cgi->param('magic')) && $cgi->param('magic') eq 'process' )
     || ( defined($cgi->param('action')) && $cgi->param('action') eq 'process_signup' )
   ) {

    $error = '';

    $cgi->param('agentnum', $agentnum) if $agentnum;
    $cgi->param('reg_code', uc(scalar($cgi->param('reg_code'))) );

    #false laziness w/agent.cgi, identical except for agentnum
    my $payby = $cgi->param('payby');
    if ( $payby eq 'CHEK' || $payby eq 'DCHK' ) {
      #$payinfo = join('@', map { $cgi->param( $payby. "_payinfo$_" ) } (1,2) );
      $cgi->param('payinfo' => $cgi->param($payby. '_payinfo1'). '@'. 
                               $cgi->param($payby. '_payinfo2')
                 );
    } else {
      $cgi->param('payinfo' => $cgi->param( $payby. '_payinfo' ) );
    }
    $cgi->param('paydate' => $cgi->param( $payby. '_month' ). '-'.
                             $cgi->param( $payby. '_year' )
               );
    $cgi->param('payname' => $cgi->param( $payby. '_payname' ) );
    $cgi->param('paycvv' => defined $cgi->param( $payby. '_paycvv' )
                              ? $cgi->param( $payby. '_paycvv' )
                              : ''
               );

    if ( $cgi->param('invoicing_list') ) {
      $cgi->param('invoicing_list' => $cgi->param('invoicing_list'). ', POST')
        if $cgi->param('invoicing_list_POST');
    } else {
      $cgi->param('invoicing_list' => 'POST' );
    }

    if ( $cgi->param('_password') ne $cgi->param('_password2') ) {
      $error = $init_data->{msgcat}{passwords_dont_match}; #msgcat
      $cgi->param('_password', '');
      $cgi->param('_password2', '');
    }

    if ( $payby =~ /^(CARD|DCRD)$/ && $cgi->param('CARD_type') ) {
      my $payinfo = $cgi->param('payinfo');
      $payinfo =~ s/\D//g;

      $payinfo =~ /^(\d{13,16})$/
        or $error ||= $init_data->{msgcat}{invalid_card}; #. $self->payinfo;
      $payinfo = $1;
      validate($payinfo)
        or $error ||= $init_data->{msgcat}{invalid_card}; #. $self->payinfo;
      cardtype($payinfo) eq $cgi->param('CARD_type')
        or $error ||= $init_data->{msgcat}{not_a}. $cgi->param('CARD_type');
    }

    if ($init_data->{emailinvoiceonly} && (length $cgi->param('invoicing_list') < 1)) {
	$error ||= $init_data->{msgcat}{illegal_or_empty_text};
    }

    unless ( $error ) {
      my $rv = new_customer( {
        map { $_ => scalar($cgi->param($_)) }
          qw( last first ss company
              address1 address2 city county state zip country
              daytime night fax

              ship_last ship_first ship_company
              ship_address1 ship_address2 ship_city ship_county ship_state
                ship_zip ship_country
              ship_daytime ship_night ship_fax

              payby payinfo paycvv paydate payname invoicing_list
              referral_custnum promo_code reg_code
              pkgpart username sec_phrase _password popnum refnum
              agentnum
            ),
          grep { /^snarf_/ } $cgi->param
      } );
      $error = $rv->{'error'};
    }
    #eslaf
    
    if ( $error eq '_decline' ) {
      print_decline();
    } elsif ( $error ) {
      #fudge the snarf info
      no strict 'refs';
      ${$_} = $cgi->param($_) foreach grep { /^snarf_/ } $cgi->param;
      print_form();
    } else {
      print_okay(
        'pkgpart' => scalar($cgi->param('pkgpart')),
      );
    }

} else {
  $error = '';
  print_form;
}

sub print_form {

  $error = "Error: $error" if $error;

  my $r = {
    $cgi->Vars,
    %{$init_data},
    'error' => $error,
  };

  $r->{pkgpart} ||= $r->{default_pkgpart};

  $r->{referral_custnum} = $r->{'ref'};
  #$cgi->delete('ref');
  #$cgi->delete('init_popstate');
  $r->{self_url} = $cgi->self_url;

  print $cgi->header( '-expires' => 'now' ),
        $signup_template->fill_in( PACKAGE => 'FS::SelfService::_signupcgi',
                                   HASH    => $r
                                 );
}

sub print_decline {
  print $cgi->header( '-expires' => 'now' ),
        $decline_template->fill_in();
}

sub print_okay {
  my %param = @_;
  my $user_agent = new HTTP::BrowserDetect $ENV{HTTP_USER_AGENT};

  $cgi->param('username') =~ /^(.+)$/
    or die "fatal: invalid username got past FS::SelfService::new_customer";
  my $username = $1;
  $cgi->param('_password') =~ /^(.+)$/
    or die "fatal: invalid password got past FS::SelfService::new_customer";
  my $password = $1;
  ( $cgi->param('first'). ' '. $cgi->param('last') ) =~ /^(.*)$/
    or die "fatal: invalid email_name got past FS::SelfService::new_customer";
  my $email_name = $1; #global for template

  #my %pop = ();
  my %popnum2pop = ();
  foreach ( @{ $init_data->{'svc_acct_pop'} } ) {
    #push @{ $pop{ $_->{state} }->{ $_->{ac} } }, $_;
    $popnum2pop{$_->{popnum}} = $_;
  }

  my( $ac, $exch, $loc);
  my $pop = $popnum2pop{$cgi->param('popnum')};
    #or die "fatal: invalid popnum got past FS::SelfService::new_customer";
  if ( $pop ) {
    ( $ac, $exch, $loc ) = ( $pop->{'ac'}, $pop->{'exch'}, $pop->{'loc'} );
  } else {
    ( $ac, $exch, $loc ) = ( '', '', ''); #presumably you're not using them.
  }

  #global for template
  my $part_pkg = ( grep { $_->{'pkgpart'} eq $param{'pkgpart'} }
                        @{ $init_data->{'part_pkg'} }
                 )[0];
  my $pkg =  $part_pkg->{'pkg'};

  if ( $ieak_template && $user_agent->windows && $user_agent->ie ) {
    #send an IEAK config
    print $cgi->header('application/x-Internet-signup'),
          $ieak_template->fill_in();
  } else { #send a simple confirmation
    print $cgi->header( '-expires' => 'now' ),
          $success_template->fill_in( HASH => {
            username   => $username,
            password   => $password,
            _password  => $password,
            email_name => $email_name,
            ac         => $ac,
            exch       => $exch,
            loc        => $loc,
            pkg        => $pkg,
            part_pkg   => \$part_pkg,
          });
  }
}

sub success_default { #html to use if you don't specify a success file
  <<'END';
<HTML><HEAD><TITLE>Signup successful</TITLE></HEAD>
<BODY BGCOLOR="#e8e8e8"><FONT SIZE=7>Signup successful</FONT><BR><BR>
Thanks for signing up!
<BR><BR>
Signup information for <%= $email_name %>:
<BR><BR>
Username: <%= $username %><BR>
Password: <%= $password %><BR>
Access number: (<%= $ac %>) / <%= $exch %> - <%= $local %><BR>
Package: <%= $pkg %><BR>
</BODY></HTML>
END
}

sub decline_default { #html to use if there is a decline
  <<'END';
<HTML><HEAD><TITLE>Processing error</TITLE></HEAD>
<BODY BGCOLOR="#e8e8e8"><FONT SIZE=7>Processing error</FONT><BR><BR>
There has been an error processing your account.  Please contact customer
support.
</BODY></HTML>
END
}

# subs for the templates...

package FS::SelfService::_signupcgi;
use HTML::Entities;
use FS::SelfService qw(regionselector expselect popselector);

