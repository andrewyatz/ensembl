=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

Bio::EnsEMBL::DBSQL::RNAProductAdaptor - Provides a means to fetch and store
RNAProduct objects from a database.

=head1 DESCRIPTION

This adaptor provides a means to retrieve and store
Bio::EnsEMBL::RNAProduct objects from/in a database.

RNAProduct objects only truly make sense in the context of their
transcripts so the recommended means to retrieve RNAProducts is
by retrieving the Transcript object first, and then fetching the
RNAProduct.

=head1 SYNOPSIS

  use Bio::EnsEMBL::Registry;

  Bio::EnsEMBL::Registry->load_registry_from_db(
    -host => 'ensembldb.ensembl.org',
    -user => 'anonymous'
  );

  $rnaproduct_adaptor =
    Bio::EnsEMBL::Registry->get_adaptor( "human", "core",
    "rnaproduct" );

  ...

=head1 METHODS

=cut

package Bio::EnsEMBL::DBSQL::RNAProductAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::RNAProduct;
use Bio::EnsEMBL::Utils::Exception qw( throw warning );
use Bio::EnsEMBL::Utils::Scalar qw( assert_ref );


use parent qw( Bio::EnsEMBL::DBSQL::BaseAdaptor );



=head2 fetch_all_by_Transcript

  Arg [1]    : Bio::EnsEMBL::Transcript $transcript
  Example    : $rps = $rnaproduct_adaptor->fetch_by_Transcript($transcript);
  Description: Retrieves RNAProducts via their associated transcript.
               If no RNAProducts are found, an empty list is returned.
  Returntype : arrayref of Bio::EnsEMBL::RNAProducts
  Exceptions : throw on incorrect argument
  Caller     : Transcript
  Status     : Stable

=cut

sub fetch_all_by_Transcript {
  my ($self, $transcript) = @_;

  assert_ref($transcript, 'Bio::EnsEMBL::Transcript');

  return $self->_fetch_direct_query(['transcript_id', $transcript->dbID(), SQL_INTEGER]);
}


=head2 fetch_by_dbID

  Arg [1]    : int $dbID
               The internal identifier of the RNAProduct to obtain
  Example    : $rnaproduct = $rnaproduct_adaptor->fetch_by_dbID(1234);
  Description: This fetches a RNAProduct object via its internal id.
               This is only debatably useful since rnaproducts do
               not make much sense outside of the context of their
               Transcript.  Consider using fetch_by_Transcript instead.
  Returntype : Bio::EnsEMBL::RNAProduct, or undef if the rnaproduct is not
               found.
  Caller     : ?
  Status     : Stable

=cut

sub fetch_by_dbID {
  my ($self, $dbID) = @_;

  throw("dbID argument is required") unless defined($dbID);

  return ($self->_fetch_direct_query(['rnaproduct_id', $dbID, SQL_INTEGER]))->[0];
}


=head2 fetch_by_stable_id

  Arg [1]    : string $stable_id
               The stable identifier of the RNAProduct to obtain
  Example    : $rnaproduct = $rnaproduct_adaptor->fetch_by_stable_id("ENSM00001");
  Description: This fetches a RNAProduct object via its stable id.
  Returntype : Bio::EnsEMBL::RNAProduct, or undef if the rnaproduct is not
               found.
  Caller     : ?
  Status     : Stable

=cut

sub fetch_by_stable_id {
  my ($self, $stable_id) = @_;

  throw("stable id argument is required") unless $stable_id;

  return ($self->_fetch_direct_query(['stable_id', $stable_id, SQL_VARCHAR]))->[0];
}


=head2 list_dbIDs

  Arg [1]    : none
  Example    : @rnaproduct_ids = @{$rnaproduct_adaptor->list_dbIDs()};
  Description: Gets an array of internal ids for all rnaproducts in the current db
  Returntype : list of ints
  Exceptions : none
  Caller     : ?
  Status     : Stable

=cut

sub list_dbIDs {
   my ($self) = @_;

   return $self->_list_dbIDs("rnaproduct");
}


=head2 _list_dbIDs

  Arg[1]      : String $table
  Arg[2]      : String $column
  Example     : $rnaproduct_adaptor->_list_dbIDs('rnaproduct', 'rnaproduct_id');
  Description : Local reimplementation to ensure multi-species rnaproducts
                are limited to their species alone
  Returntype  : ArrayRef of specified IDs
  Caller      : Internal
  Status      : Unstable
=cut

sub _list_dbIDs {
  my ($self, $table, $column) = @_;
  my $ids;
  if($self->is_multispecies()) {
    # FIXME: test this, it might not have been fully converted from TranslationAdaptor yet
    $column ||= "${table}_id";
    my $sql = <<"SQL";
select `rp`.`${column}`
from rnaproduct rp
join transcript t using (transcript_id)
join seq_region sr using (seq_region_id)
join coord_system cs using (coord_system_id)
where cs.species_id =?
SQL
    return $self->dbc()->sql_helper()->execute_simple(-SQL => $sql, -PARAMS => [$self->species_id()]);
  }
  else {
    $ids = $self->SUPER::_list_dbIDs($table, $column);
  }
  return $ids;
}


# _fetch_direct_query
#  Arg [1]    : reference to an array consisting of:
#                - the name of the column to use in the WHERE clause,
#                - the value fields from that column are to be equal to,
#                - the data type of that column (e.g. SQL_INTEGER)
#  Description: PRIVATE internal method shared between public fetch methods
#               in order to avoid duplication of SQL-query logic. NOT SAFE
#               to be handed directly to users because in its current form
#               it can be trivially exploited to inject arbitrary SQL.
#  Returntype : ArrayRef of either Bio::EnsEMBL::RNAProducts or undefs
#  Exceptions : none
#  Caller     : internal
#  Status     : At Risk (In Development)

sub _fetch_direct_query {
  my ($self, $where_args) = @_;
  my @return_data;

  my $rp_created_date =
    $self->db()->dbc()->from_date_to_seconds('created_date');
  my $rp_modified_date =
    $self->db()->dbc()->from_date_to_seconds('modified_date');

  my $sql =
    sprintf("SELECT rnaproduct_id, transcript_id, seq_start, seq_end, "
	    . "stable_id, version, %s, %s "
	    . "FROM rnaproduct "
	    . "WHERE %s = ?",
	    $rp_created_date, $rp_modified_date, $where_args->[0]);
  my $sth = $self->prepare($sql);
  $sth->bind_param(1, $where_args->[1], $where_args->[2]);
  $sth->execute();

  my $sql_data = $sth->fetchall_arrayref();
  my $transcript_adaptor = $self->db()->get_TranscriptAdaptor();
  while (my $row_ref = shift @{$sql_data}) {
    my ($rnaproduct_id, $transcript_id, $seq_start, $seq_end, $stable_id,
	$version, $created_date, $modified_date) = @{$row_ref};

    if (!defined($rnaproduct_id)) {
      push @return_data, undef;
      next;
    }

    my $rnaproduct =
      Bio::EnsEMBL::RNAProduct->new_fast( {
                             'dbID'          => $rnaproduct_id,
                             'adaptor'       => $self,
                             'start'         => $seq_start,
                             'end'           => $seq_end,
                             'stable_id'     => $stable_id,
                             'version'       => $version,
                             'created_date'  => $created_date || undef,
                             'modified_date' => $modified_date || undef,
                           } );

    my $transcript = $transcript_adaptor->fetch_by_dbID($transcript_id);
    $rnaproduct->transcript($transcript);

    push @return_data, $rnaproduct;
  }

  $sth->finish();

  return \@return_data;
}


# _tables
#  Arg [1]    : none
#  Description: PROTECTED implementation of superclass abstract method.
#               Returns the names, aliases of the tables to use for queries.
#  Returntype : list of listrefs of strings
#  Exceptions : none
#  Caller     : internal
#  Status     : Stable

sub _tables { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
  return (['rnaproduct', 'rp']);
}

1;