#!/usr/bin/perl -Tw
#
# $Id: signup.cgi,v 1.29.2.4 2002-11-29 05:14:19 ivan Exp $

use strict;
use vars qw( @payby $cgi $locales $packages $pops $init_data $error
             $last $first $ss $company $address1 $address2 $city $state $county
             $country $zip $daytime $night $fax $invoicing_list $payby $payinfo
             $paydate $payname $referral_custnum
             $pkgpart $username $password $password2 $sec_phrase $popnum
             $agentnum
             $ieak_file $ieak_template $cck_file $cck_template
             $signup_html $signup_template
             $success_html $success_template
             $decline_html $decline_template
             $ac $exch $loc
             $email_name $pkg
             $self_url
           );
use subs qw( print_form print_okay print_decline
             success_default decline_default
             expselect );
use CGI;
#use CGI::Carp qw(fatalsToBrowser);
use Text::Template;
use Business::CreditCard;
use HTTP::Headers::UserAgent 2.00;
use FS::SignupClient 0.03 qw( signup_info new_customer );

#acceptable payment methods
#
#@payby = qw( CARD BILL COMP );
#@payby = qw( CARD BILL );
#@payby = qw( CARD );
@payby = qw( CARD PREPAY );

$ieak_file = '/usr/local/freeside/ieak.template';
$cck_file = '/usr/local/freeside/cck.template';
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

if ( -e $cck_file ) {
  my $cck_txt = Text::Template::_load_text($cck_file)
    or die $Text::Template::ERROR;
  $cck_txt =~ /^(.*)$/s; #untaint the template source - it's trusted
  $cck_txt = $1;
  $cck_template = new Text::Template ( TYPE => 'STRING', SOURCE => $cck_txt )
    or die $Text::Template::ERROR;
} else {
  $cck_template = '';
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


( $locales, $packages, $pops, $init_data ) = signup_info();
@payby = @{$init_data->{'payby'}} if @{$init_data->{'payby'}};
$packages = $init_data->{agentnum2part_pkg}{$agentnum} if $agentnum;

$cgi = new CGI;

if ( defined $cgi->param('magic') ) {
  if ( $cgi->param('magic') eq 'process' ) {

    if ( $cgi->param('state') =~ /^(\w*)( \(([\w ]+)\))? ?\/ ?(\w+)$/ ) {
      $state = $1;
      $county = $3 || '';
      $country = $4;
    } elsif ( $cgi->param('state') =~ /^(\w*)$/ ) {
      $state = $1;
      $cgi->param('county') =~ /^([\w ]*)$/
        or die "illegal county: ". $cgi->param('county');
      $county = $1;
      $cgi->param('country') =~ /^(\w+)$/
        or die "illegal country: ". $cgi->param('country');
      $country = $1;
    } else {
      die "illegal state: ". $cgi->param('state');
    }

    $payby = $cgi->param('payby');
    $payinfo = $cgi->param( $payby. '_payinfo' );
    $paydate =
      $cgi->param( $payby. '_month' ). '-'. $cgi->param( $payby. '_year' );
    $payname = $cgi->param( $payby. '_payname' );

    if ( $invoicing_list = $cgi->param('invoicing_list') ) {
      $invoicing_list .= ', POST' if $cgi->param('invoicing_list_POST');
    } else {
      $invoicing_list = 'POST';
    }

    $error = '';

    $last             = $cgi->param('last');
    $first            = $cgi->param('first');
    $ss               = $cgi->param('ss');
    $company          = $cgi->param('company');
    $address1         = $cgi->param('address1');
    $address2         = $cgi->param('address2');
    $city             = $cgi->param('city');
    #$county,
    #$state,
    $zip              = $cgi->param('zip');
    #$country,
    $daytime          = $cgi->param('daytime');
    $night            = $cgi->param('night');
    $fax              = $cgi->param('fax');
    #$payby,
    #$payinfo,
    #$paydate,
    #$payname,
    #$invoicing_list,
    $referral_custnum = $cgi->param('ref');
    $pkgpart          = $cgi->param('pkgpart');
    $username         = $cgi->param('username');
    $sec_phrase       = $cgi->param('sec_phrase');
    $password         = $cgi->param('_password');
    $popnum           = $cgi->param('popnum');
    #$agentnum, #         = $cgi->param('agentnum'),

    if ( $cgi->param('_password') ne $cgi->param('_password2') ) {
      $error = $init_data->{msgcat}{passwords_dont_match}; #msgcat
      $password  = '';
      $password2 = '';
    } else {
      $password2 = $cgi->param('_password2');

      if ( $payby eq 'CARD' && $cgi->param('CARD_type') ) {
        $payinfo =~ s/\D//g;

        $payinfo =~ /^(\d{13,16})$/
          or $error ||= $init_data->{msgcat}{invalid_card}; #. $self->payinfo;
        $payinfo = $1;
        validate($payinfo)
          or $error ||= $init_data->{msgcat}{invalid_card}; #. $self->payinfo;
        cardtype($payinfo) eq $cgi->param('CARD_type')
          or $error ||= $init_data->{msgcat}{not_a}. $cgi->param('CARD_type');
      }

      $error ||= new_customer ( {
        'last'             => $last,
        'first'            => $first,
        'ss'               => $ss,
        'company'          => $company,
        'address1'         => $address1,
        'address2'         => $address2,
        'city'             => $city,
        'county'           => $county,
        'state'            => $state,
        'zip'              => $zip,
        'country'          => $country,
        'daytime'          => $daytime,
        'night'            => $night,
        'fax'              => $fax,
        'payby'            => $payby,
        'payinfo'          => $payinfo,
        'paydate'          => $paydate,
        'payname'          => $payname,
        'invoicing_list'   => $invoicing_list,
        'referral_custnum' => $referral_custnum,
        'pkgpart'          => $pkgpart,
        'username'         => $username,
        'sec_phrase'       => $sec_phrase,
        '_password'        => $password,
        'popnum'           => $popnum,
        'agentnum'         => $agentnum,
      } );

    }
    
    if ( $error eq '_decline' ) {
      print_decline();
    } elsif ( $error ) {
      print_form();
    } else {
      print_okay();
    }

  } else {
    die "unrecognized magic: ". $cgi->param('magic');
  }
} else {
  $error = '';
  $last = '';
  $first = '';
  $ss = '';
  $company = '';
  $address1 = '';
  $address2 = '';
  $city = '';
  $state = $init_data->{statedefault};
  $county = '';
  $country = $init_data->{countrydefault};
  $zip = '';
  $daytime = '';
  $night = '';
  $fax = '';
  $invoicing_list = '';
  $payby = '';
  $payinfo = '';
  $paydate = '';
  $payname = '';
  $pkgpart = '';
  $username = '';
  $password = '';
  $password2 = '';
  $sec_phrase = '';
  $popnum = '';
  $referral_custnum = $cgi->param('ref') || '';
  print_form;
}

sub print_form {

  $cgi->delete('ref');
  $self_url = $cgi->self_url;

  $error = "Error: $error" if $error;

  print $cgi->header( '-expires' => 'now' ),
        $signup_template->fill_in();

}

sub print_decline {
  print $cgi->header( '-expires' => 'now' ),
        $decline_template->fill_in();
}

sub print_okay {
  my $user_agent = new HTTP::Headers::UserAgent $ENV{HTTP_USER_AGENT};

  $cgi->param('username') =~ /^(.+)$/
    or die "fatal: invalid username got past FS::SignupClient::new_customer";
  my $username = $1;
  $cgi->param('_password') =~ /^(.+)$/
    or die "fatal: invalid password got past FS::SignupClient::new_customer";
  my $password = $1;
  ( $cgi->param('first'). ' '. $cgi->param('last') ) =~ /^(.*)$/
    or die "fatal: invalid email_name got past FS::SignupClient::new_customer";
  $email_name = $1; #global for template

  my $pop = pop_info($cgi->param('popnum'));
    #or die "fatal: invalid popnum got past FS::SignupClient::new_customer";
  if ( $pop ) {
    ( $ac, $exch, $loc ) = ( $pop->{'ac'}, $pop->{'exch'}, $pop->{'loc'} );
  } else {
    ( $ac, $exch, $loc ) = ( '', '', ''); #presumably you're not using them.
  }

  #global for template
  $pkg = ( grep { $_->{'pkgpart'} eq $pkgpart } @$packages )[0]->{'pkg'};

  if ( $ieak_template
       && $user_agent->platform eq 'ia32'
       && $user_agent->os =~ /^win/
       && ($user_agent->browser)[0] eq 'IE'
     )
  { #send an IEAK config
    print $cgi->header('application/x-Internet-signup'),
          $ieak_template->fill_in();
  } elsif ( $cck_template
            && $user_agent->platform eq 'ia32'
            && $user_agent->os =~ /^win/
            && ($user_agent->browser)[0] eq 'Netscape'
          )
  { #send a Netscape config
    my $cck_data = $cck_template->fill_in();
    print $cgi->header('application/x-netscape-autoconfigure-dialer-v2'),
          map {
            m/(.*)\s+(.*)$/;
            pack("N", length($1)). $1. pack("N", length($2)). $2;
          } split(/\n/, $cck_data);

  } else { #send a simple confirmation
    print $cgi->header( '-expires' => 'now' ),
          $success_template->fill_in();
  }
}

sub pop_info {
  my $popnum = shift;
  my $pop;
  foreach $pop ( @{$pops} ) {
    if ( $pop->{'popnum'} == $popnum ) { return $pop; }
  }
  '';
}

#horrible false laziness with FS/FS/svc_acct_pop.pm::popselector
sub popselector {
  my( $popnum, $state ) = @_;

  return '<INPUT TYPE="hidden" NAME="popnum" VALUE="">' unless @$pops;
  return $pops->[0]{city}. ', '. $pops->[0]{state}.
         ' ('. $pops->[0]{ac}. ')/'. $pops->[0]{exch}.
         '<INPUT TYPE="hidden" NAME="popnum" VALUE="'. $pops->[0]{popnum}. '">'
    if scalar(@$pops) == 1;

  my %pop = ();
  push @{ $pop{$_->{state}} }, $_ foreach @$pops;

  my $text = <<END;
    <SCRIPT>
    function opt(what,href,text) {
      var optionName = new Option(text, href, false, false)
      var length = what.length;
      what.options[length] = optionName;
    }
    
    function popstate_changed(what) {
      state = what.options[what.selectedIndex].text;
      for (var i = what.form.popnum.length;i > 0;i--)
                what.form.popnum.options[i] = null;
      what.form.popnum.options[0] = new Option("", "", false, true);
END

  foreach my $popstate ( sort { $a cmp $b } keys %pop ) {
    $text .= "\nif ( state == \"$popstate\" ) {\n";

    foreach my $pop ( @{$pop{$popstate}}) {
      my $o_popnum = $pop->{popnum};
      my $poptext =  $pop->{city}. ', '. $pop->{state}.
                     ' ('. $pop->{ac}. ')/'. $pop->{exch};

      $text .= "opt(what.form.popnum, \"$o_popnum\", \"$poptext\");\n"
    }
    $text .= "}\n";
  }

  $text .= "}\n</SCRIPT>\n";

  $text .=
    qq!<SELECT NAME="popstate" SIZE=1 onChange="popstate_changed(this)">!.
    qq!<OPTION> !;
  $text .= "<OPTION>$_" foreach sort { $a cmp $b } keys %pop;
  $text .= '</SELECT>'; #callback? return 3 html pieces?  #'</TD><TD>';

  $text .= qq!<SELECT NAME="popnum" SIZE=1><OPTION> !;
  foreach my $pop ( @$pops ) {
    $text .= qq!<OPTION VALUE="!. $pop->{popnum}. '"'.
             ( ( $popnum && $pop->{popnum} == $popnum ) ? ' SELECTED' : '' ). ">".
             $pop->{city}. ', '. $pop->{state}.
               ' ('. $pop->{ac}. ')/'. $pop->{exch};
  }
  $text .= '</SELECT>';

  $text;
}

sub expselect {
  my $prefix = shift;
  my $date = shift || '';
  my( $m, $y ) = ( 0, 0 );
  if ( $date  =~ /^(\d{4})-(\d{2})-\d{2}$/ ) { #PostgreSQL date format
    ( $m, $y ) = ( $2, $1 );
  } elsif ( $date =~ /^(\d{1,2})-(\d{1,2}-)?(\d{4}$)/ ) {
    ( $m, $y ) = ( $1, $3 );
  }
  my $return = qq!<SELECT NAME="$prefix!. qq!_month" SIZE="1">!;
  for ( 1 .. 12 ) {
    $return .= "<OPTION";
    $return .= " SELECTED" if $_ == $m;
    $return .= ">$_";
  }
  $return .= qq!</SELECT>/<SELECT NAME="$prefix!. qq!_year" SIZE="1">!;
  for ( 2001 .. 2037 ) {
    $return .= "<OPTION";
    $return .= " SELECTED" if $_ == $y;
    $return .= ">$_";
  }
  $return .= "</SELECT>";

  $return;
}

#false laziness w/FS::cust_main_county
sub regionselector {
  my ( $selected_county, $selected_state, $selected_country,
       $prefix, $onchange ) = @_;

  my $prefix = '' unless defined $prefix;

  my $countyflag = 0;

  my %cust_main_county;

#  unless ( @cust_main_county ) { #cache 
    #@cust_main_county = qsearch('cust_main_county', {} );
    #foreach my $c ( @cust_main_county ) {
    foreach my $c ( @$locales ) {
      #$countyflag=1 if $c->county;
      $countyflag=1 if $c->{county};
      #push @{$cust_main_county{$c->country}{$c->state}}, $c->county;
      #$cust_main_county{$c->country}{$c->state}{$c->county} = 1;
      $cust_main_county{$c->{country}}{$c->{state}}{$c->{county}} = 1;
    }
#  }
  $countyflag=1 if $selected_county;

  my $script_html = <<END;
    <SCRIPT>
    function opt(what,value,text) {
      var optionName = new Option(text, value, false, false);
      var length = what.length;
      what.options[length] = optionName;
    }
    function ${prefix}country_changed(what) {
      country = what.options[what.selectedIndex].text;
      for ( var i = what.form.${prefix}state.length; i >= 0; i-- )
          what.form.${prefix}state.options[i] = null;
END
      #what.form.${prefix}state.options[0] = new Option('', '', false, true);

  foreach my $country ( sort keys %cust_main_county ) {
    $script_html .= "\nif ( country == \"$country\" ) {\n";
    foreach my $state ( sort keys %{$cust_main_county{$country}} ) {
      my $text = $state || '(n/a)';
      $script_html .= qq!opt(what.form.${prefix}state, "$state", "$text");\n!;
    }
    $script_html .= "}\n";
  }

  $script_html .= <<END;
    }
    function ${prefix}state_changed(what) {
END

  if ( $countyflag ) {
    $script_html .= <<END;
      state = what.options[what.selectedIndex].text;
      country = what.form.${prefix}country.options[what.form.${prefix}country.selectedIndex].text;
      for ( var i = what.form.${prefix}county.length; i >= 0; i-- )
          what.form.${prefix}county.options[i] = null;
END

    foreach my $country ( sort keys %cust_main_county ) {
      $script_html .= "\nif ( country == \"$country\" ) {\n";
      foreach my $state ( sort keys %{$cust_main_county{$country}} ) {
        $script_html .= "\nif ( state == \"$state\" ) {\n";
          #foreach my $county ( sort @{$cust_main_county{$country}{$state}} ) {
          foreach my $county ( sort keys %{$cust_main_county{$country}{$state}} ) {
            my $text = $county || '(n/a)';
            $script_html .=
              qq!opt(what.form.${prefix}county, "$county", "$text");\n!;
          }
        $script_html .= "}\n";
      }
      $script_html .= "}\n";
    }
  }

  $script_html .= <<END;
    }
    </SCRIPT>
END

  my $county_html = $script_html;
  if ( $countyflag ) {
    $county_html .= qq!<SELECT NAME="${prefix}county" onChange="$onchange">!;
    $county_html .= '</SELECT>';
  } else {
    $county_html .=
      qq!<INPUT TYPE="hidden" NAME="${prefix}county" VALUE="$selected_county">!;
  }

  my $state_html = qq!<SELECT NAME="${prefix}state" !.
                   qq!onChange="${prefix}state_changed(this); $onchange">!;
  foreach my $state ( sort keys %{ $cust_main_county{$selected_country} } ) {
    my $text = $state || '(n/a)';
    my $selected = $state eq $selected_state ? 'SELECTED' : '';
    $state_html .= "\n<OPTION $selected VALUE=$state>$text</OPTION>"
  }
  $state_html .= '</SELECT>';

  $state_html .= '</SELECT>';

  my $country_html = qq!<SELECT NAME="${prefix}country" !.
                     qq!onChange="${prefix}country_changed(this); $onchange">!;
  my $countrydefault = $init_data->{countrydefault} || 'US';
  foreach my $country (
    sort { ($b eq $countrydefault) <=> ($a eq $countrydefault) or $a cmp $b }
      keys %cust_main_county
  ) {
    my $selected = $country eq $selected_country ? ' SELECTED' : '';
    $country_html .= "\n<OPTION$selected>$country</OPTION>"
  }
  $country_html .= '</SELECT>';

  ($county_html, $state_html, $country_html);

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
Access number: (<%= $ac %>) / $exch - $local<BR>
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

