package FS::CGI;

use strict;
use vars qw(@EXPORT_OK @ISA);
use Exporter;
use CGI;
use URI::URL;
#use CGI::Carp qw(fatalsToBrowser);
use FS::UID;

@ISA = qw(Exporter);
@EXPORT_OK = qw(header menubar idiot eidiot popurl rooturl table itable ntable
                small_custview myexit http_header);

=head1 NAME

FS::CGI - Subroutines for the web interface

=head1 SYNOPSIS

  use FS::CGI qw(header menubar idiot eidiot popurl);

  print header( 'Title', '' );
  print header( 'Title', menubar('item', 'URL', ... ) );

  idiot "error message"; 
  eidiot "error message";

  $url = popurl; #returns current url
  $url = popurl(3); #three levels up

=head1 DESCRIPTION

Provides a few common subroutines for the web interface.

=head1 SUBROUTINES

=over 4

=item header TITLE, MENUBAR

Returns an HTML header.

=cut

sub header {
  use Carp;
  carp 'FS::CGI::header deprecated; include /elements/header.html instead';

  my($title,$menubar,$etc)=@_; #$etc is for things like onLoad= etc.
  $etc = '' unless defined $etc;

  my $x =  <<END;
    <HTML>
      <HEAD>
        <TITLE>
          $title
        </TITLE>
        <META HTTP-Equiv="Cache-Control" Content="no-cache">
        <META HTTP-Equiv="Pragma" Content="no-cache">
        <META HTTP-Equiv="Expires" Content="0"> 
      </HEAD>
      <BODY BGCOLOR="#e8e8e8"$etc>
          <FONT SIZE=6>
            <CENTER>$title</CENTER>
          </FONT>
          <BR><!--<BR>-->
END
  $x .=  $menubar. "<BR><BR>" if $menubar;
  $x;
}

=item http_header

Sets an http header.

=cut

sub http_header {
  my ( $header, $value ) = @_;
  if (exists $ENV{MOD_PERL}) {
    if ( defined $HTML::Mason::Commands::r  ) { #Mason
      ## is this the correct pacakge for $r ???  for 1.0x and 1.1x ?
      if ( $header =~ /^Content-Type$/ ) {
        $HTML::Mason::Commands::r->content_type($value);
      } else {
        $HTML::Mason::Commands::r->header_out( $header => $value );
      }
    } else {
      die "http_header called in unknown environment";
    }
  } else {
    die "http_header called not running under mod_perl";
  }

}

=item menubar ITEM, URL, ...

Returns an HTML menubar.

=cut

sub menubar { #$menubar=menubar('Main Menu', '../', 'Item', 'url', ... );
  use Carp;
  carp 'FS::CGI::menubar deprecated; include /elements/menubar.html instead';

  my($item,$url,@html);
  while (@_) {
    ($item,$url)=splice(@_,0,2);
    next if $item =~ /^\s*Main\s+Menu\s*$/i;
    push @html, qq!<A HREF="$url">$item</A>!;
  }
  join(' | ',@html);
}

=item idiot ERROR

This is depriciated.  Don't use it.

Sends an HTML error message.

=cut

sub idiot {
  #warn "idiot depriciated";
  my($error)=@_;
#  my $cgi = &FS::UID::cgi();
#  if ( $cgi->isa('CGI::Base') ) {
#    no strict 'subs';
#    &CGI::Base::SendHeaders;
#  } else {
#    print $cgi->header( @FS::CGI::header );
#  }
  print <<END;
<HTML>
  <HEAD>
    <TITLE>Error processing your request</TITLE>
    <META HTTP-Equiv="Cache-Control" Content="no-cache">
    <META HTTP-Equiv="Pragma" Content="no-cache">
    <META HTTP-Equiv="Expires" Content="0"> 
  </HEAD>
  <BODY>
    <CENTER>
    <H4>Error processing your request</H4>
    </CENTER>
    Your request could not be processed because of the following error:
    <P><B>$error</B>
  </BODY>
</HTML>
END

}

=item eidiot ERROR

This is depriciated.  Don't use it.

Sends an HTML error message, then exits.

=cut

sub eidiot {
  warn "eidiot depriciated";
  $HTML::Mason::Commands::r->send_http_header
    if defined $HTML::Mason::Commands::r;
  idiot(@_);
  &myexit();
}

=item myexit

You probably shouldn't use this; but if you must:

If running under mod_perl, calles Apache::exit, otherwise, calls exit.

=cut

sub myexit {
  if (exists $ENV{MOD_PERL}) {

    if ( defined $HTML::Mason::Commands::m  ) { #Mason
      #$HTML::Mason::Commands::m->flush_buffer();
      $HTML::Mason::Commands::m->abort();
      die "shouldn't fall through to here (mason \$m->abort didn't)";
    } else {
      #??? well, it is $ENV{MOD_PERL}
      warn "running under unknown mod_perl environment; trying Apache::exit()";
      require Apache;
      Apache::exit();
    }
  } else {
    exit;
  }
}

=item popurl LEVEL

Returns current URL with LEVEL levels of path removed from the end (default 0).

=cut

sub popurl {
  my($up)=@_;
  my $cgi = &FS::UID::cgi;
  my $url_string = $cgi->isa('Apache') ? $cgi->uri : $cgi->url;
  $url_string =~ s/\?.*//;
  my $url = new URI::URL ( $url_string );
  my(@path)=$url->path_components;
  splice @path, 0-$up;
  $url->path_components(@path);
  my $x = $url->as_string;
  $x .= '/' unless $x =~ /\/$/;
  $x;
}

=item rooturl 

=cut

sub rooturl {
  # better to start with the client-provided URL
  my $cgi = &FS::UID::cgi;
  my $url_string = $cgi->isa('Apache') ? $cgi->uri : $cgi->url;
  $url_string =~ s/\?.*//;

  #even though this is kludgy
  $url_string =~ s{ / index\.html /? $ }
                  {/}x;
  $url_string =~
    s{
       /
       (browse|config|docs|edit|graph|misc|search|view|pref|rt|elements)
       /
       (process/)?
       ([\w\-\.\/]+)
       $
     }
     {}x;

  #elements because of progress-popup.html... 
  #XXX remove anything from elements that is called directly & prevent
  #those pages from being served up

  $url_string .= '/' unless $url_string =~ /\/$/;

  $url_string;

}

=item table

Returns HTML tag for beginning a table.

=cut

sub table {
  use Carp;
  carp 'FS::CGI::table deprecated; include /elements/table.html instead';

  my $col = shift;
  if ( $col ) {
    qq!<TABLE BGCOLOR="$col" BORDER=1 WIDTH="100%" CELLSPACING=0 CELLPADDING=2 BORDERCOLOR="#999999">!;
  } else { 
    '<TABLE BORDER=1 CELLSPACING=0 CELLPADDING=2 BORDERCOLOR="#999999">';
  }
}

=item itable

Returns HTML tag for beginning an (invisible) table.

=cut

sub itable {
  my $col = shift;
  my $cellspacing = shift || 0;
  my $width = ( scalar(@_) && shift ) ? '' : 'WIDTH="100%"';  #bah
  if ( $col ) {
    qq!<TABLE BGCOLOR="$col" BORDER=0 CELLSPACING=$cellspacing $width>!;
  } else {
    qq!<TABLE BORDER=0 CELLSPACING=$cellspacing $width>!;
  }
}

=item ntable

This is getting silly.

=cut

sub ntable {
  my $col = shift;
  my $cellspacing = shift || 0;
  if ( $col ) {
    qq!<TABLE BGCOLOR="$col" BORDER=0 CELLSPACING=$cellspacing>!;
  } else {
    '<TABLE BORDER CELLSPACING=0 CELLPADDING=2 BORDERCOLOR="#999999">';
  }

}

=item small_custview CUSTNUM || CUST_MAIN_OBJECT, COUNTRYDEFAULT, NOBALANCE_FLAG, URL

Sheesh. I should just switch to Mason.

=cut

sub small_custview {
  use FS::Record qw(qsearchs);
  use FS::cust_main;

  my $arg = shift;
  my $countrydefault = shift || 'US';
  my $nobalance = shift;
  my $url = shift;

  my $cust_main = ref($arg) ? $arg
                  : qsearchs('cust_main', { 'custnum' => $arg } )
    or die "unknown custnum $arg";

  my $html;
  
  $html = qq!View <A HREF="$url?! . $cust_main->custnum . '">'
    if $url;

  $html .= 'Customer #<B>'. $cust_main->custnum. '</B></A>'.
    ' - <B><FONT COLOR="#'. $cust_main->statuscolor. '">'.
    ucfirst($cust_main->status). '</FONT></B>'.
    ntable('#e8e8e8'). '<TR><TD VALIGN="top">'. ntable("#cccccc",2).
    '<TR><TD ALIGN="right" VALIGN="top">Billing<BR>Address</TD><TD BGCOLOR="#ffffff">'.
    $cust_main->getfield('last'). ', '. $cust_main->first. '<BR>';

  $html .= $cust_main->company. '<BR>' if $cust_main->company;
  $html .= $cust_main->address1. '<BR>';
  $html .= $cust_main->address2. '<BR>' if $cust_main->address2;
  $html .= $cust_main->city. ', '. $cust_main->state. '  '. $cust_main->zip. '<BR>';
  $html .= $cust_main->country. '<BR>'
    if $cust_main->country && $cust_main->country ne $countrydefault;

  $html .= '</TD></TR><TR><TD></TD><TD BGCOLOR="#ffffff">';
  if ( $cust_main->daytime && $cust_main->night ) {
    use FS::Msgcat;
    $html .= ( FS::Msgcat::_gettext('daytime') || 'Day' ).
             ' '. $cust_main->daytime.
             '<BR>'. ( FS::Msgcat::_gettext('night') || 'Night' ).
             ' '. $cust_main->night;
  } elsif ( $cust_main->daytime || $cust_main->night ) {
    $html .= $cust_main->daytime || $cust_main->night;
  }
  if ( $cust_main->fax ) {
    $html .= '<BR>Fax '. $cust_main->fax;
  }

  $html .= '</TD></TR></TABLE></TD>';

  if ( defined $cust_main->dbdef_table->column('ship_last') ) {

    my $pre = $cust_main->ship_last ? 'ship_' : '';

    $html .= '<TD VALIGN="top">'. ntable("#cccccc",2).
      '<TR><TD ALIGN="right" VALIGN="top">Service<BR>Address</TD><TD BGCOLOR="#ffffff">'.
      $cust_main->get("${pre}last"). ', '.
      $cust_main->get("${pre}first"). '<BR>';
    $html .= $cust_main->get("${pre}company"). '<BR>'
      if $cust_main->get("${pre}company");
    $html .= $cust_main->get("${pre}address1"). '<BR>';
    $html .= $cust_main->get("${pre}address2"). '<BR>'
      if $cust_main->get("${pre}address2");
    $html .= $cust_main->get("${pre}city"). ', '.
             $cust_main->get("${pre}state"). '  '.
             $cust_main->get("${pre}ship_zip"). '<BR>';
    $html .= $cust_main->get("${pre}country"). '<BR>'
      if $cust_main->get("${pre}country")
         && $cust_main->get("${pre}country") ne $countrydefault;

    $html .= '</TD></TR><TR><TD></TD><TD BGCOLOR="#ffffff">';

    if ( $cust_main->get("${pre}daytime") && $cust_main->get("${pre}night") ) {
      use FS::Msgcat;
      $html .= ( FS::Msgcat::_gettext('daytime') || 'Day' ).
               ' '. $cust_main->get("${pre}daytime").
               '<BR>'. ( FS::Msgcat::_gettext('night') || 'Night' ).
               ' '. $cust_main->get("${pre}night");
    } elsif ( $cust_main->get("${pre}daytime")
              || $cust_main->get("${pre}night") ) {
      $html .= $cust_main->get("${pre}daytime")
               || $cust_main->get("${pre}night");
    }
    if ( $cust_main->get("${pre}fax") ) {
      $html .= '<BR>Fax '. $cust_main->get("${pre}fax");
    }

    $html .= '</TD></TR></TABLE></TD>';
  }

  $html .= '</TR></TABLE>';

  $html .= '<BR>Balance: <B>$'. $cust_main->balance. '</B><BR>'
    unless $nobalance;

  # last payment might be good here too?

  $html;
}

=back

=head1 BUGS

Not OO.

Not complete.

small_custview sooooo doesn't belong here.  i should just switch to Mason.

=head1 SEE ALSO

L<CGI>, L<CGI::Base>

=cut

1;


