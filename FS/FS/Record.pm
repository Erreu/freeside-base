package FS::Record;

use strict;
use vars qw( $dbdef_file $dbdef $setup_hack $AUTOLOAD @ISA @EXPORT_OK $DEBUG
             $me %dbdef_cache );
use subs qw(reload_dbdef);
use Exporter;
use Carp qw(carp cluck croak confess);
use File::CounterFile;
use Locale::Country;
use DBI qw(:sql_types);
use DBIx::DBSchema 0.19;
use FS::UID qw(dbh checkruid getotaker datasrc driver_name);
use FS::SearchCache;
use FS::Msgcat qw(gettext);

@ISA = qw(Exporter);
@EXPORT_OK = qw(dbh fields hfields qsearch qsearchs dbdef jsearch);

$DEBUG = 0;
$me = '[FS::Record]';

#ask FS::UID to run this stuff for us later
$FS::UID::callback{'FS::Record'} = sub { 
  $File::CounterFile::DEFAULT_DIR = "/usr/local/etc/freeside/counters.". datasrc;
  $dbdef_file = "/usr/local/etc/freeside/dbdef.". datasrc;
  &reload_dbdef unless $setup_hack; #$setup_hack needed now?
};

=head1 NAME

FS::Record - Database record objects

=head1 SYNOPSIS

    use FS::Record;
    use FS::Record qw(dbh fields qsearch qsearchs dbdef);

    $record = new FS::Record 'table', \%hash;
    $record = new FS::Record 'table', { 'column' => 'value', ... };

    $record  = qsearchs FS::Record 'table', \%hash;
    $record  = qsearchs FS::Record 'table', { 'column' => 'value', ... };
    @records = qsearch  FS::Record 'table', \%hash; 
    @records = qsearch  FS::Record 'table', { 'column' => 'value', ... };

    $table = $record->table;
    $dbdef_table = $record->dbdef_table;

    $value = $record->get('column');
    $value = $record->getfield('column');
    $value = $record->column;

    $record->set( 'column' => 'value' );
    $record->setfield( 'column' => 'value' );
    $record->column('value');

    %hash = $record->hash;

    $hashref = $record->hashref;

    $error = $record->insert;
    #$error = $record->add; #deprecated

    $error = $record->delete;
    #$error = $record->del; #deprecated

    $error = $new_record->replace($old_record);
    #$error = $new_record->rep($old_record); #deprecated

    $value = $record->unique('column');

    $error = $record->ut_float('column');
    $error = $record->ut_number('column');
    $error = $record->ut_numbern('column');
    $error = $record->ut_money('column');
    $error = $record->ut_text('column');
    $error = $record->ut_textn('column');
    $error = $record->ut_alpha('column');
    $error = $record->ut_alphan('column');
    $error = $record->ut_phonen('column');
    $error = $record->ut_anything('column');
    $error = $record->ut_name('column');

    $dbdef = reload_dbdef;
    $dbdef = reload_dbdef "/non/standard/filename";
    $dbdef = dbdef;

    $quoted_value = _quote($value,'table','field');

    #depriciated
    $fields = hfields('table');
    if ( $fields->{Field} ) { # etc.

    @fields = fields 'table'; #as a subroutine
    @fields = $record->fields; #as a method call


=head1 DESCRIPTION

(Mostly) object-oriented interface to database records.  Records are currently
implemented on top of DBI.  FS::Record is intended as a base class for
table-specific classes to inherit from, i.e. FS::cust_main.

=head1 CONSTRUCTORS

=over 4

=item new [ TABLE, ] HASHREF

Creates a new record.  It doesn't store it in the database, though.  See
L<"insert"> for that.

Note that the object stores this hash reference, not a distinct copy of the
hash it points to.  You can ask the object for a copy with the I<hash> 
method.

TABLE can only be omitted when a dervived class overrides the table method.

=cut

sub new { 
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);

  unless ( defined ( $self->table ) ) {
    $self->{'Table'} = shift;
    carp "warning: FS::Record::new called with table name ". $self->{'Table'};
  }

  my $hashref = $self->{'Hash'} = shift;

  foreach my $field ( grep !defined($hashref->{$_}), $self->fields ) { 
    $hashref->{$field}='';
  }

  $self->_cache($hashref, shift) if $self->can('_cache') && @_;

  $self;
}

sub new_or_cached {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);

  $self->{'Table'} = shift unless defined ( $self->table );

  my $hashref = $self->{'Hash'} = shift;
  my $cache = shift;
  if ( defined( $cache->cache->{$hashref->{$cache->key}} ) ) {
    my $obj = $cache->cache->{$hashref->{$cache->key}};
    $obj->_cache($hashref, $cache) if $obj->can('_cache');
    $obj;
  } else {
    $cache->cache->{$hashref->{$cache->key}} = $self->new($hashref, $cache);
  }

}

sub create {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = {};
  bless ($self, $class);
  if ( defined $self->table ) {
    cluck "create constructor is depriciated, use new!";
    $self->new(@_);
  } else {
    croak "FS::Record::create called (not from a subclass)!";
  }
}

=item qsearch TABLE, HASHREF, SELECT, EXTRA_SQL, CACHE_OBJ

Searches the database for all records matching (at least) the key/value pairs
in HASHREF.  Returns all the records found as `FS::TABLE' objects if that
module is loaded (i.e. via `use FS::cust_main;'), otherwise returns FS::Record
objects.

###oops, argh, FS::Record::new only lets us create database fields.
#Normal behaviour if SELECT is not specified is `*', as in
#C<SELECT * FROM table WHERE ...>.  However, there is an experimental new
#feature where you can specify SELECT - remember, the objects returned,
#although blessed into the appropriate `FS::TABLE' package, will only have the
#fields you specify.  This might have unwanted results if you then go calling
#regular FS::TABLE methods
#on it.

=cut

sub qsearch {
  my($stable, $record, $select, $extra_sql, $cache ) = @_;
  #$stable =~ /^([\w\_]+)$/ or die "Illegal table: $table";
  #for jsearch
  $stable =~ /^([\w\s\(\)\.\,\=]+)$/ or die "Illegal table: $stable";
  $stable = $1;
  $select ||= '*';
  my $dbh = dbh;

  my $table = $cache ? $cache->table : $stable;

  my @fields = grep exists($record->{$_}), fields($table);

  my $statement = "SELECT $select FROM $stable";
  if ( @fields ) {
    $statement .= ' WHERE '. join(' AND ', map {

      my $op = '=';
      my $column = $_;
      if ( ref($record->{$_}) ) {
        $op = $record->{$_}{'op'} if $record->{$_}{'op'};
        #$op = 'LIKE' if $op =~ /^ILIKE$/i && driver_name !~ /^Pg$/i;
        if ( uc($op) eq 'ILIKE' ) {
          $op = 'LIKE';
          $record->{$_}{'value'} = lc($record->{$_}{'value'});
          $column = "LOWER($_)";
        }
        $record->{$_} = $record->{$_}{'value'}
      }

      if ( ! defined( $record->{$_} ) || $record->{$_} eq '' ) {
        if ( $op eq '=' ) {
          if ( driver_name eq 'Pg' ) {
            if ( $dbdef->table($table)->column($column)->type =~ /(int)/i ) {
              qq-( $column IS NULL )-;
            } else {
              qq-( $column IS NULL OR $column = '' )-;
            }
          } else {
            qq-( $column IS NULL OR $column = "" )-;
          }
        } elsif ( $op eq '!=' ) {
          if ( driver_name eq 'Pg' ) {
            if ( $dbdef->table($table)->column($column)->type =~ /(int)/i ) {
              qq-( $column IS NOT NULL )-;
            } else {
              qq-( $column IS NOT NULL AND $column != '' )-;
            }
          } else {
            qq-( $column IS NOT NULL AND $column != "" )-;
          }
        } else {
          if ( driver_name eq 'Pg' ) {
            qq-( $column $op '' )-;
          } else {
            qq-( $column $op "" )-;
          }
        }
      } else {
        "$column $op ?";
      }
    } @fields );
  }
  $statement .= " $extra_sql" if defined($extra_sql);

  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = $dbh->prepare($statement)
    or croak "$dbh->errstr doing $statement";

  my $bind = 1;

  foreach my $field (
    grep defined( $record->{$_} ) && $record->{$_} ne '', @fields
  ) {
    if ( $record->{$field} =~ /^\d+(\.\d+)?$/
         && $dbdef->table($table)->column($field)->type =~ /(int)/i
    ) {
      $sth->bind_param($bind++, $record->{$field}, { TYPE => SQL_INTEGER } );
    } else {
      $sth->bind_param($bind++, $record->{$field}, { TYPE => SQL_VARCHAR } );
    }
  }

#  $sth->execute( map $record->{$_},
#    grep defined( $record->{$_} ) && $record->{$_} ne '', @fields
#  ) or croak "Error executing \"$statement\": ". $sth->errstr;

  $sth->execute or croak "Error executing \"$statement\": ". $sth->errstr;

  $dbh->commit or croak $dbh->errstr if $FS::UID::AutoCommit;

  if ( eval 'scalar(@FS::'. $table. '::ISA);' ) {
    if ( eval 'FS::'. $table. '->can(\'new\')' eq \&new ) {
      #derivied class didn't override new method, so this optimization is safe
      if ( $cache ) {
        map {
          new_or_cached( "FS::$table", { %{$_} }, $cache )
        } @{$sth->fetchall_arrayref( {} )};
      } else {
        map {
          new( "FS::$table", { %{$_} } )
        } @{$sth->fetchall_arrayref( {} )};
      }
    } else {
      warn "untested code (class FS::$table uses custom new method)";
      map {
        eval 'FS::'. $table. '->new( { %{$_} } )';
      } @{$sth->fetchall_arrayref( {} )};
    }
  } else {
    cluck "warning: FS::$table not loaded; returning FS::Record objects";
    map {
      FS::Record->new( $table, { %{$_} } );
    } @{$sth->fetchall_arrayref( {} )};
  }

}

=item jsearch TABLE, HASHREF, SELECT, EXTRA_SQL, PRIMARY_TABLE, PRIMARY_KEY

Experimental JOINed search method.  Using this method, you can execute a
single SELECT spanning multiple tables, and cache the results for subsequent
method calls.  Interface will almost definately change in an incompatible
fashion.

Arguments: 

=cut

sub jsearch {
  my($table, $record, $select, $extra_sql, $ptable, $pkey ) = @_;
  my $cache = FS::SearchCache->new( $ptable, $pkey );
  my %saw;
  ( $cache,
    grep { !$saw{$_->getfield($pkey)}++ }
      qsearch($table, $record, $select, $extra_sql, $cache )
  );
}

=item qsearchs TABLE, HASHREF

Same as qsearch, except that if more than one record matches, it B<carp>s but
returns the first.  If this happens, you either made a logic error in asking
for a single item, or your data is corrupted.

=cut

sub qsearchs { # $result_record = &FS::Record:qsearchs('table',\%hash);
  my $table = $_[0];
  my(@result) = qsearch(@_);
  carp "warning: Multiple records in scalar search ($table)"
    if scalar(@result) > 1;
  #should warn more vehemently if the search was on a primary key?
  scalar(@result) ? ($result[0]) : ();
}

=back

=head1 METHODS

=over 4

=item table

Returns the table name.

=cut

sub table {
#  cluck "warning: FS::Record::table depriciated; supply one in subclass!";
  my $self = shift;
  $self -> {'Table'};
}

=item dbdef_table

Returns the DBIx::DBSchema::Table object for the table.

=cut

sub dbdef_table {
  my($self)=@_;
  my($table)=$self->table;
  $dbdef->table($table);
}

=item get, getfield COLUMN

Returns the value of the column/field/key COLUMN.

=cut

sub get {
  my($self,$field) = @_;
  # to avoid "Use of unitialized value" errors
  if ( defined ( $self->{Hash}->{$field} ) ) {
    $self->{Hash}->{$field};
  } else { 
    '';
  }
}
sub getfield {
  my $self = shift;
  $self->get(@_);
}

=item set, setfield COLUMN, VALUE

Sets the value of the column/field/key COLUMN to VALUE.  Returns VALUE.

=cut

sub set { 
  my($self,$field,$value) = @_;
  $self->{'Hash'}->{$field} = $value;
}
sub setfield {
  my $self = shift;
  $self->set(@_);
}

=item AUTLOADED METHODS

$record->column is a synonym for $record->get('column');

$record->column('value') is a synonym for $record->set('column','value');

=cut

# readable/safe
sub AUTOLOAD {
  my($self,$value)=@_;
  my($field)=$AUTOLOAD;
  $field =~ s/.*://;
  if ( defined($value) ) {
    confess "errant AUTOLOAD $field for $self (arg $value)"
      unless $self->can('setfield');
    $self->setfield($field,$value);
  } else {
    confess "errant AUTOLOAD $field for $self (no args)"
      unless $self->can('getfield');
    $self->getfield($field);
  }    
}

# efficient
#sub AUTOLOAD {
#  my $field = $AUTOLOAD;
#  $field =~ s/.*://;
#  if ( defined($_[1]) ) {
#    $_[0]->setfield($field, $_[1]);
#  } else {
#    $_[0]->getfield($field);
#  }    
#}

=item hash

Returns a list of the column/value pairs, usually for assigning to a new hash.

To make a distinct duplicate of an FS::Record object, you can do:

    $new = new FS::Record ( $old->table, { $old->hash } );

=cut

sub hash {
  my($self) = @_;
  %{ $self->{'Hash'} }; 
}

=item hashref

Returns a reference to the column/value hash.

=cut

sub hashref {
  my($self) = @_;
  $self->{'Hash'};
}

=item insert

Inserts this record to the database.  If there is an error, returns the error,
otherwise returns false.

=cut

sub insert {
  my $self = shift;

  my $error = $self->check;
  return $error if $error;

  #single-field unique keys are given a value if false
  #(like MySQL's AUTO_INCREMENT)
  foreach ( $self->dbdef_table->unique->singles ) {
    $self->unique($_) unless $self->getfield($_);
  }
  #and also the primary key
  my $primary_key = $self->dbdef_table->primary_key;
  $self->unique($primary_key) 
    if $primary_key && ! $self->getfield($primary_key);

  #false laziness w/delete
  my @fields =
    grep defined($self->getfield($_)) && $self->getfield($_) ne "",
    $self->fields
  ;
  my @values = map { _quote( $self->getfield($_), $self->table, $_) } @fields;
  #eslaf

  my $statement = "INSERT INTO ". $self->table. " ( ".
      join( ', ', @fields ).
    ") VALUES (".
      join( ', ', @values ).
    ")"
  ;
  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = dbh->prepare($statement) or return dbh->errstr;

  my $h_sth;
  if ( defined $dbdef->table('h_'. $self->table) ) {
    my $h_statement = $self->_h_statement('insert');
    warn "[debug]$me $h_statement\n" if $DEBUG > 2;
    $h_sth = dbh->prepare($h_statement) or return dbh->errstr;
  } else {
    $h_sth = '';
  }

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE'; 
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  $sth->execute or return $sth->errstr;
  $h_sth->execute or return $h_sth->errstr if $h_sth;
  dbh->commit or croak dbh->errstr if $FS::UID::AutoCommit;

  '';
}

=item add

Depriciated (use insert instead).

=cut

sub add {
  cluck "warning: FS::Record::add depriciated!";
  insert @_; #call method in this scope
}

=item delete

Delete this record from the database.  If there is an error, returns the error,
otherwise returns false.

=cut

sub delete {
  my $self = shift;

  my $statement = "DELETE FROM ". $self->table. " WHERE ". join(' AND ',
    map {
      $self->getfield($_) eq ''
        #? "( $_ IS NULL OR $_ = \"\" )"
        ? ( driver_name =~ /^Pg$/i
              ? "$_ IS NULL"
              : "( $_ IS NULL OR $_ = \"\" )"
          )
        : "$_ = ". _quote($self->getfield($_),$self->table,$_)
    } ( $self->dbdef_table->primary_key )
          ? ( $self->dbdef_table->primary_key)
          : $self->fields
  );
  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = dbh->prepare($statement) or return dbh->errstr;

  my $h_sth;
  if ( defined $dbdef->table('h_'. $self->table) ) {
    my $h_statement = $self->_h_statement('delete');
    warn "[debug]$me $h_statement\n" if $DEBUG > 2;
    $h_sth = dbh->prepare($h_statement) or return dbh->errstr;
  } else {
    $h_sth = '';
  }

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE'; 
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $rc = $sth->execute or return $sth->errstr;
  #not portable #return "Record not found, statement:\n$statement" if $rc eq "0E0";
  $h_sth->execute or return $h_sth->errstr if $h_sth;
  dbh->commit or croak dbh->errstr if $FS::UID::AutoCommit;

  #no need to needlessly destoy the data either (causes problems actually)
  #undef $self; #no need to keep object!

  '';
}

=item del

Depriciated (use delete instead).

=cut

sub del {
  cluck "warning: FS::Record::del depriciated!";
  &delete(@_); #call method in this scope
}

=item replace OLD_RECORD

Replace the OLD_RECORD with this one in the database.  If there is an error,
returns the error, otherwise returns false.

=cut

sub replace {
  my ( $new, $old ) = ( shift, shift );
  warn "[debug]$me $new ->replace $old\n" if $DEBUG;

  return "Records not in same table!" unless $new->table eq $old->table;

  my $primary_key = $old->dbdef_table->primary_key;
  return "Can't change $primary_key"
    if $primary_key
       && ( $old->getfield($primary_key) ne $new->getfield($primary_key) );

  my $error = $new->check;
  return $error if $error;

  my @diff = grep $new->getfield($_) ne $old->getfield($_), $old->fields;
  unless ( @diff ) {
    carp "[warning]$me $new -> replace $old: records identical";
    return '';
  }

  my $statement = "UPDATE ". $old->table. " SET ". join(', ',
    map {
      "$_ = ". _quote($new->getfield($_),$old->table,$_) 
    } @diff
  ). ' WHERE '.
    join(' AND ',
      map {
        $old->getfield($_) eq ''
          #? "( $_ IS NULL OR $_ = \"\" )"
          ? ( driver_name =~ /^Pg$/i
                ? "$_ IS NULL"
                : "( $_ IS NULL OR $_ = \"\" )"
            )
          : "$_ = ". _quote($old->getfield($_),$old->table,$_)
      } ( $primary_key ? ( $primary_key ) : $old->fields )
    )
  ;
  warn "[debug]$me $statement\n" if $DEBUG > 1;
  my $sth = dbh->prepare($statement) or return dbh->errstr;

  my $h_old_sth;
  if ( defined $dbdef->table('h_'. $old->table) ) {
    my $h_old_statement = $old->_h_statement('replace_old');
    warn "[debug]$me $h_old_statement\n" if $DEBUG > 2;
    $h_old_sth = dbh->prepare($h_old_statement) or return dbh->errstr;
  } else {
    $h_old_sth = '';
  }

  my $h_new_sth;
  if ( defined $dbdef->table('h_'. $new->table) ) {
    my $h_new_statement = $new->_h_statement('replace_new');
    warn "[debug]$me $h_new_statement\n" if $DEBUG > 2;
    $h_new_sth = dbh->prepare($h_new_statement) or return dbh->errstr;
  } else {
    $h_new_sth = '';
  }

  local $SIG{HUP} = 'IGNORE';
  local $SIG{INT} = 'IGNORE';
  local $SIG{QUIT} = 'IGNORE'; 
  local $SIG{TERM} = 'IGNORE';
  local $SIG{TSTP} = 'IGNORE';
  local $SIG{PIPE} = 'IGNORE';

  my $rc = $sth->execute or return $sth->errstr;
  #not portable #return "Record not found (or records identical)." if $rc eq "0E0";
  $h_old_sth->execute or return $h_old_sth->errstr if $h_old_sth;
  $h_new_sth->execute or return $h_new_sth->errstr if $h_new_sth;
  dbh->commit or croak dbh->errstr if $FS::UID::AutoCommit;

  '';

}

=item rep

Depriciated (use replace instead).

=cut

sub rep {
  cluck "warning: FS::Record::rep depriciated!";
  replace @_; #call method in this scope
}

=item check

Not yet implemented, croaks.  Derived classes should provide a check method.

=cut

sub check {
  confess "FS::Record::check not implemented; supply one in subclass!";
}

sub _h_statement {
  my( $self, $action ) = @_;

  my @fields =
    grep defined($self->getfield($_)) && $self->getfield($_) ne "",
    $self->fields
  ;
  my @values = map { _quote( $self->getfield($_), $self->table, $_) } @fields;

  "INSERT INTO h_". $self->table. " ( ".
      join(', ', qw(history_date history_user history_action), @fields ).
    ") VALUES (".
      join(', ', time, dbh->quote(getotaker()), dbh->quote($action), @values).
    ")"
  ;
}

=item unique COLUMN

Replaces COLUMN in record with a unique number.  Called by the B<add> method
on primary keys and single-field unique columns (see L<DBIx::DBSchema::Table>).
Returns the new value.

=cut

sub unique {
  my($self,$field) = @_;
  my($table)=$self->table;

  #croak("&FS::UID::checkruid failed") unless &checkruid;

  croak "Unique called on field $field, but it is ",
        $self->getfield($field),
        ", not null!"
    if $self->getfield($field);

  #warn "table $table is tainted" if is_tainted($table);
  #warn "field $field is tainted" if is_tainted($field);

  my($counter) = new File::CounterFile "$table.$field",0;
# hack for web demo
#  getotaker() =~ /^([\w\-]{1,16})$/ or die "Illegal CGI REMOTE_USER!";
#  my($user)=$1;
#  my($counter) = new File::CounterFile "$user/$table.$field",0;
# endhack

  my($index)=$counter->inc;
  $index=$counter->inc
    while qsearchs($table,{$field=>$index}); #just in case

  $index =~ /^(\d*)$/;
  $index=$1;

  $self->setfield($field,$index);

}

=item ut_float COLUMN

Check/untaint floating point numeric data: 1.1, 1, 1.1e10, 1e10.  May not be
null.  If there is an error, returns the error, otherwise returns false.

=cut

sub ut_float {
  my($self,$field)=@_ ;
  ($self->getfield($field) =~ /^(\d+\.\d+)$/ ||
   $self->getfield($field) =~ /^(\d+)$/ ||
   $self->getfield($field) =~ /^(\d+\.\d+e\d+)$/ ||
   $self->getfield($field) =~ /^(\d+e\d+)$/)
    or return "Illegal or empty (float) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_number COLUMN

Check/untaint simple numeric data (whole numbers).  May not be null.  If there
is an error, returns the error, otherwise returns false.

=cut

sub ut_number {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\d+)$/
    or return "Illegal or empty (numeric) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_numbern COLUMN

Check/untaint simple numeric data (whole numbers).  May be null.  If there is
an error, returns the error, otherwise returns false.

=cut

sub ut_numbern {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\d*)$/
    or return "Illegal (numeric) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_money COLUMN

Check/untaint monetary numbers.  May be negative.  Set to 0 if null.  If there
is an error, returns the error, otherwise returns false.

=cut

sub ut_money {
  my($self,$field)=@_;
  $self->setfield($field, 0) if $self->getfield($field) eq '';
  $self->getfield($field) =~ /^(\-)? ?(\d*)(\.\d{2})?$/
    or return "Illegal (money) $field: ". $self->getfield($field);
  #$self->setfield($field, "$1$2$3" || 0);
  $self->setfield($field, ( ($1||''). ($2||''). ($3||'') ) || 0);
  '';
}

=item ut_text COLUMN

Check/untaint text.  Alphanumerics, spaces, and the following punctuation
symbols are currently permitted: ! @ # $ % & ( ) - + ; : ' " , . ? / =
May not be null.  If there is an error, returns the error, otherwise returns
false.

=cut

sub ut_text {
  my($self,$field)=@_;
  #warn "msgcat ". \&msgcat. "\n";
  #warn "notexist ". \&notexist. "\n";
  #warn "AUTOLOAD ". \&AUTOLOAD. "\n";
  $self->getfield($field) =~ /^([\w \!\@\#\$\%\&\(\)\-\+\;\:\'\"\,\.\?\/\=]+)$/
    or return gettext('illegal_or_empty_text'). " $field: ".
               $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_textn COLUMN

Check/untaint text.  Alphanumerics, spaces, and the following punctuation
symbols are currently permitted: ! @ # $ % & ( ) - + ; : ' " , . ? /
May be null.  If there is an error, returns the error, otherwise returns false.

=cut

sub ut_textn {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^([\w \!\@\#\$\%\&\(\)\-\+\;\:\'\"\,\.\?\/\=]*)$/
    or return gettext('illegal_text'). " $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_alpha COLUMN

Check/untaint alphanumeric strings (no spaces).  May not be null.  If there is
an error, returns the error, otherwise returns false.

=cut

sub ut_alpha {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\w+)$/
    or return "Illegal or empty (alphanumeric) $field: ".
              $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_alpha COLUMN

Check/untaint alphanumeric strings (no spaces).  May be null.  If there is an
error, returns the error, otherwise returns false.

=cut

sub ut_alphan {
  my($self,$field)=@_;
  $self->getfield($field) =~ /^(\w*)$/ 
    or return "Illegal (alphanumeric) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_phonen COLUMN [ COUNTRY ]

Check/untaint phone numbers.  May be null.  If there is an error, returns
the error, otherwise returns false.

Takes an optional two-letter ISO country code; without it or with unsupported
countries, ut_phonen simply calls ut_alphan.

=cut

sub ut_phonen {
  my( $self, $field, $country ) = @_;
  return $self->ut_alphan($field) unless defined $country;
  my $phonen = $self->getfield($field);
  if ( $phonen eq '' ) {
    $self->setfield($field,'');
  } elsif ( $country eq 'US' || $country eq 'CA' ) {
    $phonen =~ s/\D//g;
    $phonen =~ /^(\d{3})(\d{3})(\d{4})(\d*)$/
      or return gettext('illegal_phone'). " $field: ". $self->getfield($field);
    $phonen = "$1-$2-$3";
    $phonen .= " x$4" if $4;
    $self->setfield($field,$phonen);
  } else {
    warn "warning: don't know how to check phone numbers for country $country";
    return $self->ut_textn($field);
  }
  '';
}

=item ut_ip COLUMN

Check/untaint ip addresses.  IPv4 only for now.

=cut

sub ut_ip {
  my( $self, $field ) = @_;
  $self->getfield($field) =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
    or return "Illegal (IP address) $field: ". $self->getfield($field);
  for ( $1, $2, $3, $4 ) { return "Illegal (IP address) $field" if $_ > 255; }
  $self->setfield($field, "$1.$2.$3.$4");
  '';
}

=item ut_ipn COLUMN

Check/untaint ip addresses.  IPv4 only for now.  May be null.

=cut

sub ut_ipn {
  my( $self, $field ) = @_;
  if ( $self->getfield($field) =~ /^()$/ ) {
    $self->setfield($field,'');
    '';
  } else {
    $self->ut_ip($field);
  }
}

=item ut_domain COLUMN

Check/untaint host and domain names.

=cut

sub ut_domain {
  my( $self, $field ) = @_;
  #$self->getfield($field) =~/^(\w+\.)*\w+$/
  $self->getfield($field) =~/^(([\w\-]+\.)*\w+)$/
    or return "Illegal (domain) $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_name COLUMN

Check/untaint proper names; allows alphanumerics, spaces and the following
punctuation: , . - '

May not be null.

=cut

sub ut_name {
  my( $self, $field ) = @_;
  $self->getfield($field) =~ /^([\w \,\.\-\']+)$/
    or return gettext('illegal_name'). " $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_zip COLUMN

Check/untaint zip codes.

=cut

sub ut_zip {
  my( $self, $field, $country ) = @_;
  if ( $country eq 'US' ) {
    $self->getfield($field) =~ /\s*(\d{5}(\-\d{4})?)\s*$/
      or return gettext('illegal_zip'). " $field for country $country: ".
                $self->getfield($field);
    $self->setfield($field,$1);
  } else {
    $self->getfield($field) =~ /^\s*(\w[\w\-\s]{2,8}\w)\s*$/
      or return gettext('illegal_zip'). " $field: ". $self->getfield($field);
    $self->setfield($field,$1);
  }
  '';
}

=item ut_country COLUMN

Check/untaint country codes.  Country names are changed to codes, if possible -
see L<Locale::Country>.

=cut

sub ut_country {
  my( $self, $field ) = @_;
  unless ( $self->getfield($field) =~ /^(\w\w)$/ ) {
    if ( $self->getfield($field) =~ /^([\w \,\.\(\)\']+)$/ 
         && country2code($1) ) {
      $self->setfield($field,uc(country2code($1)));
    }
  }
  $self->getfield($field) =~ /^(\w\w)$/
    or return "Illegal (country) $field: ". $self->getfield($field);
  $self->setfield($field,uc($1));
  '';
}

=item ut_anything COLUMN

Untaints arbitrary data.  Be careful.

=cut

sub ut_anything {
  my( $self, $field ) = @_;
  $self->getfield($field) =~ /^(.*)$/s
    or return "Illegal $field: ". $self->getfield($field);
  $self->setfield($field,$1);
  '';
}

=item ut_enum COLUMN CHOICES_ARRAYREF

Check/untaint a column, supplying all possible choices, like the "enum" type.

=cut

sub ut_enum {
  my( $self, $field, $choices ) = @_;
  foreach my $choice ( @$choices ) {
    if ( $self->getfield($field) eq $choice ) {
      $self->setfield($choice);
      return '';
    }
  }
  return "Illegal (enum) field $field: ". $self->getfield($field);
}

=item ut_foreign_key COLUMN FOREIGN_TABLE FOREIGN_COLUMN

Check/untaint a foreign column key.  Call a regular ut_ method (like ut_number)
on the column first.

=cut

sub ut_foreign_key {
  my( $self, $field, $table, $foreign ) = @_;
  qsearchs($table, { $foreign => $self->getfield($field) })
    or return "Can't find $field ". $self->getfield($field).
              " in $table.$foreign";
  '';
}

=item ut_foreign_keyn COLUMN FOREIGN_TABLE FOREIGN_COLUMN

Like ut_foreign_key, except the null value is also allowed.

=cut

sub ut_foreign_keyn {
  my( $self, $field, $table, $foreign ) = @_;
  $self->getfield($field)
    ? $self->ut_foreign_key($field, $table, $foreign)
    : '';
}

=item fields [ TABLE ]

This can be used as both a subroutine and a method call.  It returns a list
of the columns in this record's table, or an explicitly specified table.
(See L<DBIx::DBSchema::Table>).

=cut

# Usage: @fields = fields($table);
#        @fields = $record->fields;
sub fields {
  my $something = shift;
  my $table;
  if ( ref($something) ) {
    $table = $something->table;
  } else {
    $table = $something;
  }
  #croak "Usage: \@fields = fields(\$table)\n   or: \@fields = \$record->fields" unless $table;
  my($table_obj) = $dbdef->table($table);
  confess "Unknown table $table" unless $table_obj;
  $table_obj->columns;
}

=back

=head1 SUBROUTINES

=over 4

=item reload_dbdef([FILENAME])

Load a database definition (see L<DBIx::DBSchema>), optionally from a
non-default filename.  This command is executed at startup unless
I<$FS::Record::setup_hack> is true.  Returns a DBIx::DBSchema object.

=cut

sub reload_dbdef {
  my $file = shift || $dbdef_file;

  unless ( exists $dbdef_cache{$file} ) {
    warn "[debug]$me loading dbdef for $file\n" if $DEBUG;
    $dbdef_cache{$file} = DBIx::DBSchema->load( $file )
                            or die "can't load database schema from $file";
  } else {
    warn "[debug]$me re-using cached dbdef for $file\n" if $DEBUG;
  }
  $dbdef = $dbdef_cache{$file};
}

=item dbdef

Returns the current database definition.  See L<DBIx::DBSchema>.

=cut

sub dbdef { $dbdef; }

=item _quote VALUE, TABLE, COLUMN

This is an internal function used to construct SQL statements.  It returns
VALUE DBI-quoted (see L<DBI/"quote">) unless VALUE is a number and the column
type (see L<DBIx::DBSchema::Column>) does not end in `char' or `binary'.

=cut

sub _quote {
  my($value, $table, $column) = @_;
  my $column_obj = $dbdef->table($table)->column($column);
  my $column_type = $column_obj->type;

  if ( $value eq '' && $column_type =~ /^int/ ) {
    if ( $column_obj->null ) {
      'NULL';
    } else {
      cluck "WARNING: Attempting to set non-null integer $table.$column null; ".
            "using 0 instead";
      0;
    }
  } elsif ( $value =~ /^\d+(\.\d+)?$/ && 
            ! $column_type =~ /(char|binary|text)$/i ) {
    $value;
  } else {
    dbh->quote($value);
  }
}

=item hfields TABLE

This is depriciated.  Don't use it.

It returns a hash-type list with the fields of this record's table set true.

=cut

sub hfields {
  carp "warning: hfields is depriciated";
  my($table)=@_;
  my(%hash);
  foreach (fields($table)) {
    $hash{$_}=1;
  }
  \%hash;
}

sub _dump {
  my($self)=@_;
  join("\n", map {
    "$_: ". $self->getfield($_). "|"
  } (fields($self->table)) );
}

sub DESTROY { return; }

#sub DESTROY {
#  my $self = shift;
#  #use Carp qw(cluck);
#  #cluck "DESTROYING $self";
#  warn "DESTROYING $self";
#}

#sub is_tainted {
#             return ! eval { join('',@_), kill 0; 1; };
#         }

=back

=head1 BUGS

This module should probably be renamed, since much of the functionality is
of general use.  It is not completely unlike Adapter::DBI (see below).

Exported qsearch and qsearchs should be depriciated in favor of method calls
(against an FS::Record object like the old search and searchs that qsearch
and qsearchs were on top of.)

The whole fields / hfields mess should be removed.

The various WHERE clauses should be subroutined.

table string should be depriciated in favor of DBIx::DBSchema::Table.

No doubt we could benefit from a Tied hash.  Documenting how exists / defined
true maps to the database (and WHERE clauses) would also help.

The ut_ methods should ask the dbdef for a default length.

ut_sqltype (like ut_varchar) should all be defined

A fallback check method should be provided which uses the dbdef.

The ut_money method assumes money has two decimal digits.

The Pg money kludge in the new method only strips `$'.

The ut_phonen method only checks US-style phone numbers.

The _quote function should probably use ut_float instead of a regex.

All the subroutines probably should be methods, here or elsewhere.

Probably should borrow/use some dbdef methods where appropriate (like sub
fields)

As of 1.14, DBI fetchall_hashref( {} ) doesn't set fetchrow_hashref NAME_lc,
or allow it to be set.  Working around it is ugly any way around - DBI should
be fixed.  (only affects RDBMS which return uppercase column names)

ut_zip should take an optional country like ut_phone.

=head1 SEE ALSO

L<DBIx::DBSchema>, L<FS::UID>, L<DBI>

Adapter::DBI from Ch. 11 of Advanced Perl Programming by Sriram Srinivasan.

=cut

1;

