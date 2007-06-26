package FS::Cron::notify;

use strict;
use vars qw( @ISA @EXPORT_OK $DEBUG );
use Exporter;
use FS::UID qw( dbh );
use FS::Record qw(qsearch);
use FS::cust_main;
use FS::cust_pkg;

@ISA = qw( Exporter );
@EXPORT_OK = qw ( notify_flat_delay );
$DEBUG = 0;

sub notify_flat_delay {

  my %opt = @_;

  my $oldAutoCommit = $FS::UID::AutoCommit;
  $DEBUG = 1 if $opt{'v'};
  
  #we're at now now (and later).
  my($time) = $^T;

  # select * from cust_pkg where
  my $where_pkg = <<"END";
    where ( cancel is null or cancel = 0 )
      and ( bill > 0 )
      and
      0 < ( select count(*) from part_pkg
              where cust_pkg.pkgpart = part_pkg.pkgpart
                and part_pkg.plan = 'flat_delayed'
                and 0 < ( select count (*) from part_pkg_option
                            where part_pkg.pkgpart = part_pkg_option.pkgpart
                              and part_pkg_option.optionname = 'recur_notify'
                              and part_pkg_option.optionvalue > 0
                              and 0 <= $time
                                + cast(part_pkg_option.optionvalue as integer)
                                  * 86400
                                - cust_pkg.bill
                              and ( cust_pkg.expire is null
                                or  cust_pkg.expire > $time
                                  + cast(part_pkg_option.optionvalue as integer)
                                    * 86400
/*                            and ( cust_pkg.adjourn is null
                                or  cust_pkg.adjourn > $time
-- Should notify suspended ones   + cast(part_pkg_option.optionvalue as integer)
                                    * 86400
*/
                                  )
                        )
          )
      and
      0 = ( select count(*) from cust_pkg_option
              where cust_pkg.pkgnum = cust_pkg_option.pkgnum
                and cust_pkg_option.optionname = 'impending_recur_notification_sent'
                and cust_pkg_option.optionvalue = 1
          )
END
  
  if ($opt{a}) {
    $where_pkg .= <<END;
      and 0 < ( select count(*) from cust_main
                  where cust_pkg.custnum = cust_main.custnum
                    and cust_main.agentnum = $opt{a}
              )
END
  }
  
  my @cust_pkg;
  if ( @ARGV ) {
    $where_pkg .= "and ( " . join( "OR ", map { "custnum = $_" } @ARGV) . " )";
  } 

  my $orderby = "order by custnum, bill";

  my $extra_sql = "$where_pkg $orderby";

  @cust_pkg = qsearch('cust_pkg', {}, '', $extra_sql );
  
  my @packages = ();
  my @recurdates = ();
  my @cust_pkgs = ();
  while ( scalar(@cust_pkg) ) {
    my $cust_main = $cust_pkg[0]->cust_main;
    my $custnum = $cust_pkg[0]->custnum;
    warn "working on $custnum" if $DEBUG;
    while (scalar(@cust_pkg)){
      last if ($cust_pkg[0]->custnum != $custnum);
      warn "storing information on " . $cust_pkg[0]->pkgnum if $DEBUG;
      push @packages, $cust_pkg[0]->part_pkg->pkg;
      push @recurdates, $cust_pkg[0]->bill;
      push @cust_pkgs, $cust_pkg[0];
      shift @cust_pkg;
    }
    my $error = 
      $cust_main->notify( 'impending_recur_template',
                          'extra_fields' => { 'packages'   => \@packages,
                                              'recurdates' => \@recurdates,
                                              'package'    => $packages[0],
                                              'recurdate'  => $recurdates[0],
                                            },
                        );
    warn "Error notifying, custnum ". $cust_main->custnum. ": $error" if $error;

    unless ($error) { 
      local $SIG{HUP} = 'IGNORE';
      local $SIG{INT} = 'IGNORE';
      local $SIG{QUIT} = 'IGNORE';
      local $SIG{TERM} = 'IGNORE';
      local $SIG{TSTP} = 'IGNORE';

      my $oldAutoCommit = $FS::UID::AutoCommit;
      local $FS::UID::AutoCommit = 0;
      my $dbh = dbh;

      for (@cust_pkgs) {
        my %options = ($_->options,  'impending_recur_notification_sent' => 1 );
        $error = $_->replace( $_, options => \%options );
        if ($error){
          $dbh->rollback or die $dbh->errstr if $oldAutoCommit;
          die "Error updating package options for customer". $cust_main->custnum.
               ": $error" if $error;
        }
      }

      $dbh->commit or die $dbh->errstr if $oldAutoCommit;

    }

    @packages = ();
    @recurdates = ();
    @cust_pkgs = ();
  
  }

  dbh->commit or die dbh->errstr if $oldAutoCommit;

}

1;
