package Dist::Zilla::Plugin::ModuleBuild;
# ABSTRACT: build a Build.PL that uses Module::Build

use Moose;
with (
  'Dist::Zilla::Role::BuildPL',
  'Dist::Zilla::Role::PrereqSource',
  'Dist::Zilla::Role::FileGatherer',
  'Dist::Zilla::Role::TextTemplate',
);

use Dist::Zilla::Dialect;

use namespace::autoclean;

use CPAN::Meta::Requirements 2.121; # requirements_for_module
use Dist::Zilla::File::InMemory;
use List::Util 'first';
use Data::Dumper;

=head1 DESCRIPTION

This plugin will create a F<Build.PL> for installing the dist using
L<Module::Build>.

=cut

=attr mb_version

B<Optional:> Specify the minimum version of L<Module::Build> to depend on.

Defaults to 0.3601 if a sharedir is being used, otherwise 0.28.

=attr mb_class

B<Optional:> Specify the class to use to create the build object.  Defaults
to C<Module::Build> itself.  If another class is specified, then the value
of mb_lib will be used to generate a line like C<use lib 'inc'> to be added
to the generated Build.PL file.

=attr mb_lib

B<Optional:> Specify the list of directories to be passed to lib when using 
mb_class. Defaults to C<inc>. 

=attr build_element

Anything given in a C<build_element> option will be added as a build element
with Module::Build's L<add_build_element> method.

=cut

has 'mb_version' => (
  isa => 'Str',
  is  => 'rw',
  lazy => 1,
  default => sub {
    my $self = shift;
    keys %{$self->zilla->_share_dir_map} ? '0.3601' : '0.28';
  },
);

has 'mb_class' => (
  isa => 'Str',
  is  => 'rw',
  default => 'Module::Build',
);

has 'mb_lib' => (
  isa => 'Str',
  is  => 'rw',
  default => 'inc'
);

has 'build_element' => (
  isa => 'ArrayRef[Str]',
  is  => 'rw',
  default => sub { [] },
);

sub mvp_multivalue_args { return qw(build_element) }

my $template = q|
# This file was automatically generated by {{ $generated_by }}.
use strict;
use warnings;

use Module::Build {{ $plugin->mb_version }};
{{ $plugin->_use_custom_class }}

my {{ $module_build_args }}

my {{ $fallback_build_prereqs }}

unless ( eval { Module::Build->VERSION(0.4004) } ) {
  delete $module_build_args{test_requires};
  $module_build_args{build_requires} = \%fallback_build_requires;
}

my $build = {{ $plugin->mb_class }}->new(%module_build_args);
{{ $plugin->_add_build_elements }}

$build->create_build_script;
|;

sub _use_custom_class {
  my ($self) = @_;
  my $class = $self->mb_class;
  if ( $class eq 'Module::Build' ) {
    return "";
  }
  else {
    return sprintf "use lib qw{%s}; use $class;", join ' ', split ',', $self->mb_lib;
  }
}

sub _dump_as {
  my ($self, $ref, $name) = @_;
  require Data::Dumper;
  my $dumper = Data::Dumper->new( [ $ref ], [ $name ] );
  $dumper->Sortkeys( 1 );
  $dumper->Indent( 1 );
  $dumper->Useqq( 1 );
  return $dumper->Dump;
}

sub _add_build_elements {
  my @elems = @{ shift->build_element } or return '';
  return '$build->add_build_element($_) for qw(' . join(' ', @elems) . ');';
}

sub register_prereqs {
  my ($self) = @_;

  $self->zilla->register_prereqs(
    { phase => 'configure' },
    'Module::Build' => $self->mb_version,
  );

  $self->zilla->register_prereqs(
    { phase => 'build' },
    'Module::Build' => $self->mb_version,
  );
}

sub module_build_args {
  my ($self) = @_;

  my @exe_files = map { $_->name }
    @{ $self->zilla->find_files(':ExecFiles') };

  $self->log_fatal("can't install files with whitespace in their names")
    if grep { /\s/ } @exe_files;

  my $prereqs = $self->zilla->prereqs;
  my %prereqs = (
    configure_requires => $prereqs->requirements_for(qw(configure requires)),
    build_requires     => $prereqs->requirements_for(qw(build     requires)),
    test_requires      => $prereqs->requirements_for(qw(test      requires)),
    requires           => $prereqs->requirements_for(qw(runtime   requires)),
    recommends         => $prereqs->requirements_for(qw(runtime   recommends)),
  );

  my $name = $self->zilla->name =~ s/-/::/gr;

  return {
    module_name   => $name,
    license       => $self->zilla->license->meta_yml_name,
    dist_abstract => $self->zilla->abstract,
    dist_name     => $self->zilla->name,
    dist_version  => $self->zilla->version,
    dist_author   => [ $self->zilla->authors ],
    @exe_files ? ( script_files  => [ sort @exe_files ] ) : (),
    ( keys %{$self->zilla->_share_dir_map} ? (share_dir => $self->zilla->_share_dir_map) : ()),

    (map {; my $modules = $prereqs{$_}->as_string_hash; keys %$modules ? ( $_ => $modules ) : () } keys %prereqs),
    recursive_test_files => 1,
  };
}

sub fallback_build_requires {
  my $self = shift;
  my $prereqs = $self->zilla->prereqs;
  my $merged = CPAN::Meta::Requirements->new;
  for my $phase ( qw/build test/ ) {
    my $req = $prereqs->requirements_for($phase, 'requires');
    $merged->add_requirements( $req );
  };
  return $self->_dump_as( $merged->as_string_hash, '*fallback_build_requires' );
}

sub gather_files {
  my ($self) = @_;

  require Dist::Zilla::File::InMemory;

  my $file = Dist::Zilla::File::InMemory->new({
    name    => 'Build.PL',
    content => $template,   # template evaluated later
  });

  $self->add_file($file);
  return;
}

sub setup_installer {
  my ($self) = @_;

  $self->log_fatal("can't build Build.PL; license has no known META.yml value")
    unless $self->zilla->license->meta_yml_name;

  my $module_build_args = $self->module_build_args;

  $self->__module_build_args($module_build_args);

  my $dumped_args = $self->_dump_as($module_build_args, '*module_build_args');

  my $fallback_build_requires = $self->fallback_build_requires;

  my $file = first { $_->name eq 'Build.PL' } @{$self->zilla->files};

  $self->log_debug([ 'updating contents of Build.PL in memory' ]);
  my $content = $self->fill_in_string(
    $file->content,
    {
      plugin                  => \$self,
      module_build_args       => \$dumped_args,
      fallback_build_prereqs  => \$fallback_build_requires,
      generated_by            => \sprintf("%s v%s",
                                    ref($self), $self->VERSION || '(dev)'),
    },
  );

  $file->content($content);

  return;
}

# XXX:  Just here to facilitate testing. -- rjbs, 2010-03-20
has __module_build_args => (
  is   => 'rw',
  isa  => 'HashRef',
);

__PACKAGE__->meta->make_immutable;
1;

=head1 SEE ALSO

Core Dist::Zilla plugins:
L<@Basic|Dist::Zilla::PluginBundle::Basic>,
L<@Filter|Dist::Zilla::PluginBundle::Filter>,
L<MakeMaker|Dist::Zilla::Plugin::MakeMaker>,
L<Manifest|Dist::Zilla::Plugin::Manifest>.

Dist::Zilla roles:
L<BuildPL|Dist::Zilla::Role::BuildPL>.

=cut

