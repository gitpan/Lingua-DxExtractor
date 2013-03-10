package Lingua::DxExtractor;

use 5.008008;
use strict;
use warnings;
use Carp;

our $VERSION = '1.07';

use Text::Sentence qw( split_sentences );
use Lingua::NegEx qw( negation_scope );

use Class::MakeMethods (
  'Template::Hash:array' => [
        'target_words', 'skip_words'
  ],
  'Template::Hash:scalar' => [
        'orig_text', 'final_answer', 'ambiguous',
  ],
  'Template::Hash:hash' => [
        'target_sentence', 'negex_debug',
  ],
);

######################################################################

sub new {
  my $callee = shift;
  my $package = ref $callee || $callee;
  my $self = shift;
  bless $self, $package;
  croak if ! $self->target_words;
  return $self;
}

sub process_text {
  my ($self,$text) = @_;
  $self->orig_text( $text );
  return $self->final_answer if $self->examine_text;
  return;
}

sub examine_text {
  my $self = shift;
  my $text = $self->orig_text;
  return if ! $text;
  $text =~ s/\s+/ /gxms;
  my @sentences = split_sentences( $text );
  foreach my $line ( @sentences ) {
    next if scalar (grep { $line =~ /\b$_\b/ixms } @{$self->skip_words});
    next if ! scalar(grep { $line =~ /\b$_\b/ixms } @{$self->target_words});
    $self->target_sentence->{ $line } = 'present';
    my $n_scope = negation_scope( $line );
    if ( $n_scope ) {
      $self->negex_debug->{ $line } = @$n_scope[0] . ' - ' . @$n_scope[1];
      my @words = ( map { s/\W//xms; $_; } ( split /\s/xms, $line ) );
      my $term_in_scope;
      foreach my $c ( @$n_scope[0] .. @$n_scope[1] ) {
        my @match = grep { $words[ $c ] =~ /$_/ixms } @{$self->target_words};
	if ( scalar @match ) {
	  $term_in_scope = 1;
        }
      }
      if ( $term_in_scope ) {
        $self->target_sentence->{ $line } = 'absent';
      }
    }
  }
  if ( scalar keys %{$self->target_sentence} ) {
    my %final_answer;
    while ( my($sentence,$answer) = each %{$self->target_sentence} ) {
      $final_answer{ $answer }++;
      $self->final_answer( $answer );
    }
    if ( scalar keys %final_answer > 1 ) {
      $self->ambiguous( 1 );
      $final_answer{ 'absent' } ||= 0;
      $final_answer{ 'present' } ||= 0;

      if ( $final_answer{ 'absent' } > $final_answer{ 'present' } ) {
        $self->final_answer( 'absent' );
      } elsif ( $final_answer{ 'present' } > $final_answer{ 'absent' } ) {
        $self->final_answer( 'present' );
      } else {
	# There are an equal number of absent/present findings - defaulting to present
        $self->final_answer( 'present' );
      }
    }
  } elsif ( ! scalar keys %{$self->target_sentence} ) {
    $self->final_answer( 'absent' );
  }
  return 1;
}

sub debug {
  my $self = shift;
  my $out = "Target Words:\n" . (join ', ', @{$self->target_words}) . "\n\n";
  $out .= "Skip Words:\n " . (join ', ', @{$self->skip_words}) . "\n\n";
  $out .= "Sentences:\n";
  my $c = 1;
  while ( my($sentence,$answer) = each %{$self->target_sentence} ) {
    $out .= "$c) $sentence\nAnswer: $answer\n";
    if ( defined $self->negex_debug->{ $sentence } ) {
      $out .= 'NegEx: ' . $self->negex_debug->{ $sentence } . "\n";
    }
    $c++;
  }
  $out .= "\nFinal Answer: " . $self->final_answer . "\n";;
  $out .= 'Ambiguous: ' . ($self->ambiguous ? 'Yes' : 'No');
  return $out;
}

sub clear {
  my $self = shift;
  $self->orig_text( '' );
  $self->target_sentence( {} );
  $self->final_answer( '' );
  $self->ambiguous( '' );
  return;
}

1;

=head1 NAME

Lingua::DxExtractor - Extract the presence or absence of a clinical condition from radiology reports. 

=head1 SYNOPSIS

  use Lingua::DxExtractor;

  $extractor = Lingua::DxExtractor->new( {
    target_words => [  qw( embolus embolism emboli defect pe clot clots ) ],
    skip_words => [ qw( history indication technique nondiagnostic ) ],
  } );

  $text = 'Indication: To rule out pulmonary embolism.\nFindings: There is no evidence of vascular filling defect...\n";

  $final_answer = $extractor->process_text( $text ); # 'absent' or 'present'
  $is_final_answer_ambiguous = $extractor->ambiguous; # 1 or 0
  $debug = $extractor->debug;

  $original_text = $extractor->orig_text;
  $final_answer = $extractor->final_answer;
  $ambiguous = $extractor->ambiguous;

  $extractor->clear; # clears orig_text, final_answer, target_sentence and ambiguous 

  
=head1 DESCRIPTION

A tool to be used to look for the presence or absence of a clinical condition as reported in radiology reports. The extractor reports a 'final answer', 'absent' or 'present', as well as reports whether this answer is 'ambiguous' or not.

The 'use case' for this is when performing a research project with a large number of records and you need to identify a subset based on a diagnostic entity, you can use this tool to reduce the number of charts that have to be manually examined. In this 'use case' I wanted to keep the sensitivity as high as possible in order to not miss real cases.

The radiographic reports don't require textual preprocessing however clearly the selection of target_words and skip_words requires reading through reports to get a sense of what vocabulary is being used in the particular dataset that is being evaluated.

Negated terms are identified using Lingua::NegEx which is a perl implementation of Wendy Chapman's NegEx algorithm.

=head1 SUBROUTINES/METHODS

=head3 new( { target_words => \@target_words, skip_words => \@skip_words, } );

=head4 target_words( \@words );

This is a list of words that describe the clinical entity in question. All forms of the entity in question need to explicitly stated since the package is currently not using lemmatization or stemming.

=head4 skip_words( \@skip );

Not required. This is a list of words that can be used to eliminate sentences in the text that might confuse the extractor. For example most radiographic reports start with a brief description of the indication for the test. This statement may state the clinical entity in question but does not mean it is present in the study (ie. Indication: to rule out pulmonary embolism).

=head2 EXPORT

None by default.

=head1 DEPENDENCIES

L<Lingua::NegEx>

L<Text::Sentence>

L<Class::MakeMethods>

=head1 SEE ALSO

A web form to try out Lingua::DxExtractor: http://www.iturrate.com/DxExtractor.html

A similar project using the ConText algorithm: http://www.ncbi.nlm.nih.gov/pubmed/21459155

=head1 TO DO

1. Add lemmatization or stemming to target_words so you don't have to explicitly write out all forms of words.

2. Add ConText support.

3. Add checking for addended reports.

=head1 AUTHOR

Eduardo Iturrate, E<lt>ed@iturrate.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Eduardo Iturrate

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
