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


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

Bio::EnsEMBL::Utils::Tree::Interval

=head1 SYNOPSIS


=head1 DESCRIPTION

Class representing a dynamic, i.e. mutable, interval tree implemented as an augmented AVL balanced binary tree.

=head1 METHODS

=cut

package Bio::EnsEMBL::Utils::Tree::Interval;

use strict;

use Data::Dumper;

use Bio::EnsEMBL::Utils::Scalar qw(assert_ref);
use Bio::EnsEMBL::Utils::Exception qw(throw warning info);

# the modules providing the underlying implementation,
# either XS or pure perl fallback
my $XS = 'Bio::EnsEMBL::XS::Utils::Tree::Interval';
my $PP = 'Bio::EnsEMBL::Utils::Tree::Interval::PP';

# if XS is used, version at least 1.3.1 is required
my $VERSION_XS = '1.3.1';

my @public_methods = qw/ insert find /;

# import either XS or PP methods into namespace
unless ($Bio::EnsEMBL::Utils::Tree::Interval::IMPL) {
  # first check if XS is available and try to load it,
  # otherwise fall back to PP implementation
  _load_xs() or _load_pp() or throw "Couldn't load implementation: $@";
}


=head2 new

=cut

sub new {
  my $caller = shift;
  my $class = ref($caller) || $caller;

  # for ($XS|$PP)::new(0);
  return eval qq| $Bio::EnsEMBL::Utils::Tree::Interval::IMPL\::new( \$caller ) | unless $caller;

  if (my $self = $Bio::EnsEMBL::Utils::Tree::Interval::IMPL->new(@_)) {
    $self->{_IMPL} = $Bio::EnsEMBL::Utils::Tree::Interval::IMPL;
    bless($self, $class);
    return $self
  }

  return;
}

sub _load_xs {
  _load($XS, $VERSION_XS);
}

sub _load_pp {
  _load($PP);
}

sub _load {
  my ($module, $version) = @_;
  $version ||= '';

  eval qq| use $module $version |;
  info(sprintf("Cannot load %s interval tree implementation, will fall back to PP", $module eq $XS?'XS':'PP'), 2000)
    and return if $@;

  push @Bio::EnsEMBL::Utils::Tree::Interval::ISA, $module;
  $Bio::EnsEMBL::Utils::Tree::Interval::IMPL = $module;

  local $^W;
  no strict qw(refs);

  for my $method (@public_methods) {
    *{"Bio::EnsEMBL::Utils::Tree::Interval::$method"} = \&{"$module\::$method"};
  }
  
  return 1;
}

1;
