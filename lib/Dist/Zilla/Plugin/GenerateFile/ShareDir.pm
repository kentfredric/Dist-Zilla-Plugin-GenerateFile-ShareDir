use strict;
use warnings;
package Dist::Zilla::Plugin::GenerateFile::ShareDir;
# ABSTRACT: Create files in the build, based on a template located in a dist sharedir
# KEYWORDS: plugin distribution generate create file sharedir template
# vim: set ts=8 sts=4 sw=4 tw=115 et :

our $VERSION = '0.006';

use Moose;
with (
    'Dist::Zilla::Role::FileGatherer',
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::TextTemplate',
);

use MooseX::SlurpyConstructor 1.2;
use Moose::Util 'find_meta';
use File::ShareDir 'dist_file';
use Path::Tiny 0.04;
use Encode;
use namespace::autoclean;

has dist => (
    is => 'ro', isa => 'Str',
    init_arg => '-dist',
    lazy => 1,
    default => sub {(my $dist = find_meta(shift)->name) =~ s/::/-/g; $dist },
);

has filename => (
    init_arg => '-destination_filename',
    is => 'ro', isa => 'Str',
    required => 1,
);

has source_filename => (
    init_arg => '-source_filename',
    is => 'ro', isa => 'Str',
    lazy => 1,
    default => sub { shift->filename },
);

has encoding => (
    init_arg => '-encoding',
    is => 'ro', isa => 'Str',
    lazy => 1,
    default => 'UTF-8',
);

has _extra_args => (
    isa => 'HashRef[Str]',
    init_arg => undef,
    lazy => 1,
    default => sub { {} },
    traits => ['Hash'],
    handles => { _extra_args => 'elements' },
    slurpy => 1,
);

around BUILDARGS => sub
{
    my $orig = shift;
    my $class = shift;

    my $args = $class->$orig(@_);
    $args->{'-destination_filename'} = delete $args->{'-filename'} if exists $args->{'-filename'};

    return $args;
};

around dump_config => sub
{
    my ($orig, $self) = @_;
    my $config = $self->$orig;

    $config->{'' . __PACKAGE__} = {
        # XXX FIXME - it seems META.* does not like the leading - in field
        # names! something is wrong with the serialization process.
        'dist' => $self->dist,
        'encoding' => $self->encoding,
        'source_filename' => $self->source_filename,
        'destination_filename' => $self->filename,
        $self->_extra_args,
    };
    return $config;
};

sub gather_files
{
    my $self = shift;

    # this should die if the file does not exist
    my $file = dist_file($self->dist, $self->source_filename);

    my $content = path($file)->slurp_raw;
    $content = Encode::decode($self->encoding, $content, Encode::FB_CROAK());

    require Dist::Zilla::File::InMemory;
    $self->add_file(Dist::Zilla::File::InMemory->new(
        name => $self->filename,
        encoding => $self->encoding,    # only used in Dist::Zilla 5.000+
        content => $content,
    ));
}

sub munge_file
{
    my ($self, $file) = @_;

    return unless $file->name eq $self->filename;
    $self->log_debug([ 'updating contents of %s in memory', $file->name ]);

    my $content = $self->fill_in_string(
        $file->content,
        {
            $self->_extra_args,     # must be first
            dist => \($self->zilla),
            plugin => \$self,
        },
    );

    # older Dist::Zilla wrote out all files :raw, so we need to encode manually here.
    $content = Encode::encode($self->encoding, $content, Encode::FB_CROAK()) if Dist::Zilla->VERSION < 5.000;

    $file->content($content);
}

__PACKAGE__->meta->make_immutable;
__END__

=pod

=for Pod::Coverage::TrustPod
    gather_files
    munge_file

=for :header
=for stopwords sharedir

=head1 SYNOPSIS

In your F<dist.ini>:

    [GenerateFile::ShareDir]
    -dist = Dist::Zilla::PluginBundle::Author::ME
    -source_filename = my_data_template.txt
    -destination_filename = examples/my_data.txt
    key1 = value to pass to template
    key2 = another value to pass to template

=head1 DESCRIPTION

Generates a file in your dist, indicated by C<-destination_file>, based on the
L<Text::Template> located in the C<-source_file> of C<-dist>'s
L<distribution sharedir|File::ShareDir>. Any extra config values are passed
along to the template, in addition to C<$zilla> and C<$plugin> objects.

I expect that usually the C<-dist> that contains the template will be either a
plugin bundle, so you can generate a custom-tailored file in your dist, or a
plugin that subclasses this one.  (Otherwise, you can just as easily use
L<[GatherDir::Template]|Dist::Zilla::Plugin::GatherDir::Template>
or L<[GenerateFile]|Dist::Zilla::Plugin::GenerateFile>
to generate the file directly, without needing a sharedir.)

=head1 OPTIONS

All unrecognized keys/values will be passed to the template as is.
Recognized options are:

=head2 C<-dist>

The distribution name to use when finding the sharedir (see L<File::ShareDir>
and L<Dist::Zilla::Plugin::ShareDir>). Defaults to the dist corresponding to
the running plugin.

=head2 C<-destination_filename> or C<-filename>

The filename to generate in the distribution being built. Required.

=head2 C<-source_filename>

The filename in the sharedir to use to generate the new file. Defaults to the
same filename and path as C<-destination_file>.

=head2 C<-encoding>

The encoding of the source file; will also be used for the encoding of the
destination file. Defaults to UTF-8.

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-GenerateFile-ShareDir>
(or L<bug-Dist-Zilla-Plugin-GenerateFile-ShareDir@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-GenerateFile-ShareDir@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=for stopwords templated

=for :list
* L<File::ShareDir>
* L<Dist::Zilla::Plugin::ShareDir>
* L<Text::Template>
* L<[GatherDir::Template]|Dist::Zilla::Plugin::GatherDir::Template> - gather a file from the dist, and then pass it through a template
* L<[GenerateFile]|Dist::Zilla::Plugin::GenerateFile> - generate a (possibly-templated) file purely based on data in F<dist.ini>

=cut
