package FS::TicketSystem::RT_External;

use strict;
use vars qw( $conf $default_queueid
             $priority_field $priority_field_queue $field
	     $dbh $external_url );
use URI::Escape;
use FS::UID qw(dbh);
use FS::Record qw(qsearchs);
use FS::cust_main;

FS::UID->install_callback( sub { 
  my $conf = new FS::Conf;
  $default_queueid = $conf->config('ticket_system-default_queueid');
  $priority_field =
    $conf->config('ticket_system-custom_priority_field');
  if ( $priority_field ) {
    $priority_field_queue =
      $conf->config('ticket_system-custom_priority_field_queue');
    $field = $priority_field_queue
                  ? $priority_field_queue. '.%7B'. $priority_field. '%7D'
                  : $priority_field;
  } else {
    $priority_field_queue = '';
    $field = '';
  }

  $external_url = '';
  $dbh = dbh;
  if ($conf->config('ticket_system') eq 'RT_External') {
    my ($datasrc, $user, $pass) = $conf->config('ticket_system-rt_external_datasrc');
    $dbh = DBI->connect($datasrc, $user, $pass, { 'ChopBlanks' => 1 })
      or die "RT_External DBI->connect error: $DBI::errstr\n";

    $external_url = $conf->config('ticket_system-rt_external_url');
  }

} );

sub num_customer_tickets {
  my( $self, $custnum, $priority ) = @_;

  my( $from_sql, @param) = $self->_from_customer( $custnum, $priority );

  my $sql = "SELECT COUNT(*) $from_sql";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr. " preparing $sql";
  $sth->execute(@param)         or die $sth->errstr. " executing $sql";

  $sth->fetchrow_arrayref->[0];

}

sub customer_tickets {
  my( $self, $custnum, $limit, $priority ) = @_;
  $limit ||= 0;

  my( $from_sql, @param) = $self->_from_customer( $custnum, $priority );
  my $sql = "SELECT tickets.*, queues.name".
            ( length($priority) ? ", objectcustomfieldvalues.content" : '' ).
            " $from_sql ORDER BY priority DESC LIMIT $limit";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr. "preparing $sql";
  $sth->execute(@param)         or die $sth->errstr. "executing $sql";

  #munge column names???  #httemplate/view/cust_main/tickets.html has column
  #names that might not make sense now...
  $sth->fetchall_arrayref({});

}

sub _from_customer {
  my( $self, $custnum, $priority ) = @_;

  my @param = ();
  my $join = '';
  my $where = '';
  if ( defined($priority) ) {

    my $queue_sql = " ObjectCustomFields.ObjectId = ( SELECT id FROM queues
                                                       WHERE queues.name = ? )
                      OR ( ? = '' AND ObjectCustomFields.ObjectId = 0 )";

    my $customfield_sql =
      "customfield = ( 
        SELECT CustomFields.Id FROM CustomFields
                  JOIN ObjectCustomFields
                    ON ( CustomFields.id = ObjectCustomFields.CustomField )
         WHERE LookupType = 'RT::Queue-RT::Ticket'
           AND name = ?
           AND ( $queue_sql )
       )";

    push @param, $priority_field,
                 $priority_field_queue,
                 $priority_field_queue;

    if ( length($priority) ) {
      #$where = "    
      #  and ? = ( select content from TicketCustomFieldValues
      #             where ticket = tickets.id
      #               and customfield = ( select id from customfields
      #                                    where name = ?
      #                                      and ( $queue_sql )
      #                                 )
      #          )
      #";
      unshift @param, $priority;

      $join = "JOIN ObjectCustomFieldValues
                 ON ( tickets.id = ObjectCustomFieldValues.ObjectId )";
      
      $where = " AND content = ?
                 AND ObjectType = 'RT::Ticket'
                 AND $customfield_sql";

    } else {

      $where =
               "AND 0 = ( SELECT count(*) FROM ObjectCustomFieldValues
                           WHERE ObjectId    = tickets.id
                             AND ObjectType  = 'RT::Ticket'
                             AND $customfield_sql
                        )
               ";
    }

  }

  my $sql = "
                    FROM tickets
                    JOIN queues ON ( tickets.queue = queues.id )
                    JOIN links ON ( tickets.id = links.localbase )
                    $join 
       WHERE ( status = 'new' OR status = 'open' OR status = 'stalled' )
         AND target = 'freeside://freeside/cust_main/$custnum'
         $where
  ";

  ( $sql, @param );

}

sub href_customer_tickets {
  my( $self, $custnum, $priority ) = @_;

  my $href = $self->baseurl;

  #i snarfed this from an RT bookmarked search, it could be unescaped in the
  #source for readability and run through uri_escape
  $href .= 
    'Search/Results.html?Order=ASC&Query=%20MemberOf%20%3D%20%27freeside%3A%2F%2Ffreeside%2Fcust_main%2F'.
    $custnum.
    '%27%20%20AND%20%28%20Status%20%3D%20%27open%27%20%20OR%20Status%20%3D%20%27new%27%20%20OR%20Status%20%3D%20%27stalled%27%20%29%20'
  ;

  if ( defined($priority) && $field && $priority_field_queue ) {
    $href .= 'AND%20Queue%20%3D%20%27'. $priority_field_queue. '%27%20';
  }
  if ( defined($priority) && $field ) {
    $href .= '%20AND%20%27CF.'. $field. '%27%20';
    if ( $priority ) {
      $href .= '%3D%20%27'. $priority. '%27%20';
    } else {
      $href .= 'IS%20%27NULL%27%20';
    }
  }

  $href .= '&Rows=100'.
           '&OrderBy=id&Page=1'.
           '&Format=%27%20%20%20%3Cb%3E%3Ca%20href%3D%22'.
	   $self->baseurl.
	   'Ticket%2FDisplay.html%3Fid%3D__id__%22%3E__id__%3C%2Fa%3E%3C%2Fb%3E%2FTITLE%3A%23%27%2C%20%0A%27%3Cb%3E%3Ca%20href%3D%22'.
	   $self->baseurl.
	   'Ticket%2FDisplay.html%3Fid%3D__id__%22%3E__Subject__%3C%2Fa%3E%3C%2Fb%3E%2FTITLE%3ASubject%27%2C%20%0A%27__Status__%27%2C%20';

  if ( defined($priority) && $field ) {
    $href .= '%0A%27__CustomField.'. $field. '__%2FTITLE%3ASeverity%27%2C%20';
  }

  $href .= '%0A%27__QueueName__%27%2C%20%0A%27__OwnerName__%27%2C%20%0A%27__Priority__%27%2C%20%0A%27__NEWLINE__%27%2C%20%0A%27%27%2C%20%0A%27%3Csmall%3E__Requestors__%3C%2Fsmall%3E%27%2C%20%0A%27%3Csmall%3E__CreatedRelative__%3C%2Fsmall%3E%27%2C';

  if ( defined($priority) && $field ) {
    $href .=   '%20%0A%27__-__%27%2C';
  }

  $href .= '%20%0A%27%3Csmall%3E__ToldRelative__%3C%2Fsmall%3E%27%2C%20%0A%27%3Csmall%3E__LastUpdatedRelative__%3C%2Fsmall%3E%27%2C%20%0A%27%3Csmall%3E__TimeLeft__%3C%2Fsmall%3E%27';

  $href;

}

sub href_new_ticket {
  my( $self, $custnum_or_cust_main, $requestors ) = @_;

  my( $custnum, $cust_main );
  if ( ref($custnum_or_cust_main) ) {
    $cust_main = $custnum_or_cust_main;
    $custnum = $cust_main->custnum;
  } else {
    $custnum = $custnum_or_cust_main;
    $cust_main = qsearchs('cust_main', { 'custnum' => $custnum } );
  }
  my $queueid = $cust_main->agent->ticketing_queueid || $default_queueid;

  $self->baseurl.
  'Ticket/Create.html?'.
    "Queue=$queueid".
    "&new-MemberOf=freeside://freeside/cust_main/$custnum".
    ( $requestors ? '&Requestors='. uri_escape($requestors) : '' )
    ;
}

sub href_ticket {
  my($self, $ticketnum) = @_;
  $self->baseurl. 'Ticket/Display.html?id='.$ticketnum;
}

sub queues {
  my($self) = @_;

  my $sql = "SELECT id, name FROM queues WHERE disabled = 0";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr. " preparing $sql";
  $sth->execute()               or die $sth->errstr. " executing $sql";

  map { $_->[0] => $_->[1] } @{ $sth->fetchall_arrayref([]) };

}

sub queue {
  my($self, $queueid) = @_;

  return '' unless $queueid;

  my $sql = "SELECT name FROM queues WHERE id = ?";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr. " preparing $sql";
  $sth->execute($queueid)       or die $sth->errstr. " executing $sql";

  $sth->fetchrow_arrayref->[0];

}

sub baseurl {
  #my $self = shift;
  $external_url;
}

1;

