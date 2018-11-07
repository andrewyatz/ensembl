=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2018] EMBL-European Bioinformatics Institute

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

package XrefParser::VGNCParser;

use strict;
use warnings;
use Carp;
use Text::CSV;

use parent qw( XrefParser::HGNCParser );

sub run {
  my ($self, $ref_arg) = @_;

  my $source_id    = $ref_arg->{source_id};
  my $species_id   = $ref_arg->{species_id};
  my $files        = $ref_arg->{files};
  my $verbose      = $ref_arg->{verbose} // 0;
  my $dbi          = $ref_arg->{dbi} // $self->dbi;


  if ( (!defined $source_id) or (!defined $species_id) or (!defined $files) ) {
    croak "Need to pass source_id, species_id and files as pairs";
  }

  my $file = shift @{$files};

  my $count = 0;

  my $file_io = $self->get_filehandle($file);

  if ( !defined $file_io ) {
    croak "Can't open VGNC file $file\n";
  }

  my $source_name = $self->get_source_name_for_source_id($source_id, $dbi);

  # Create a hash of all valid taxon_ids for this species
  my %species2tax = $self->species_id2taxonomy($dbi);
  my @tax_ids = @{$species2tax{$species_id}};
  my %taxonomy2species_id = map{ $_=>$species_id } @tax_ids;

  my $input_file = Text::CSV->new({
    sep_char       => "\t",
    empty_is_undef => 1
  }) or croak "Cannot use file $file: ".Text::CSV->error_diag ();

  # header must contain these columns
  my @required_columns = qw(
    taxon_id
    ensembl_gene_id
    vgnc_id
    symbol
    name
    alias_symbol
    prev_symbol
  );

  # get header columns
  my @columns = @{ $input_file->getline( $file_io ) };

  # die if some required_column is not in columns
  foreach my $colname (@required_columns) {
    if ( !grep { /$colname/xms } @columns ) {
      croak "Can't find required column $colname in VGNC file $file\n";
    }
  }

  $input_file->column_names( @columns );

  while ( my $data = $input_file->getline_hr( $file_io ) ) {

    # skip data for other species
    next if ( !exists $taxonomy2species_id{$data->{'taxon_id'}} );

    if ( $data->{'ensembl_gene_id'} ) {              # Ensembl direct xref
      $self->add_to_direct_xrefs({
        stable_id  => $data->{'ensembl_gene_id'},
        type       => 'gene',
        acc        => $data->{'vgnc_id'},
        label      => $data->{'symbol'},
        desc       => $data->{'name'},
        dbi        => $dbi,
        source_id  => $source_id,
        species_id => $species_id
      });

      $self->add_synonyms_for_hgnc({
        source_id  => $source_id,
        name       => $data->{'vgnc_id'},
        species_id => $species_id,
        dbi        => $dbi,
        dead       => $data->{'alias_symbol'},
        alias      => $data->{'prev_symbol'}
      });

      $count++;
    }

  }

  $input_file->eof or croak "Error parsing file $file: " . $input_file->error_diag();
  $file_io->close();

  if($verbose){
    print "Loaded a total of $count xrefs\n";
  }

  return 0; # successful
}

1;
