package Lingua::DxExtractor;

use 5.008008;
use strict;
use warnings;

our $VERSION = '1.02';

use Text::Sentence qw( split_sentences );
use Lingua::NegEx;

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
  die unless $self->target_words;
  return $self;
}

sub process_text {
  my ($self,$text) = @_;
  $self->orig_text( $text );
  $self->examine_text;
  return $self->final_answer;
}

sub examine_text {
  my $self = shift;
  my @sentences = split_sentences( $self->orig_text );
  foreach my $line ( @sentences ) {
    next if grep { $line =~ /\b$_\b/i } @{$self->skip_words};
    next unless grep { $line =~ /\b$_\b/i } @{$self->target_words};

    $self->target_sentence->{ $line } = 'present';
    my $n_scope = negation_scope( $line );
    $self->negex_debug->{ $line } = $n_scope;

    if ( $n_scope eq '-1' ) {
      # affirmed
      $self->target_sentence->{ $line } = 'present';
    } elsif ( $n_scope eq '-2' ) {
      # negated 
      $self->target_sentence->{ $line } = 'absent';

    } else {
      # "Negated in this scope: $n_scope";
      $n_scope =~ /(\d+)\s-\s(\d+)/;
      my @words = split /\s/, $line;
      my $term_in_scope;
      foreach my $c ( $1 .. $2 ) {
	$term_in_scope = 1 if grep { $words[ $c ] =~ /$_/i } @{$self->target_words};
      }
      $self->target_sentence->{ $line } = 'absent' if $term_in_scope;
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
}

sub debug {
  my $self = shift;
  my $out = "DxExtractor Debug:\n";
  $out .= "Target Words: " . (join ', ', @{$self->target_words}) . "\n";
  $out .= "Skip Words: " . (join ', ', @{$self->skip_words}) . "\n";
  $out .= "Sentences:\n";
  while ( my($sentence,$answer) = each %{$self->target_sentence} ) {
    $out .= "$sentence\n$answer\n"; 
    $out .= "NegEx: " . $self->negex_debug->{ $sentence } . "\n";
  }
  $out .= "Final Answer: " . $self->final_answer . "\n";;
  $out .= "Ambiguous: " . ($self->ambiguous ? 'Yes' : 'No');
  return $out;
}

sub reset {
  my $self = shift;
  $self->orig_text( '' );
  $self->target_sentence( {} );
  $self->final_answer( '' );
  $self->ambiguous( '' );
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

  $extractor->reset; # start all over again

  
=head1 DESCRIPTION

A tool to be used to look for the presence or absence of a clinical condition as reported in radiology reports. The extractor reports a 'final answer', 'absent' or 'present', as well as reports whether this answer is 'ambiguous' or not.

The 'use case' for this is when performing a research project with a large number of records and you need to identify a subset based on a diagnostic entity, you can use this tool to reduce the number of charts that have to be manually examined. In this 'use case' I wanted to keep the sensitivity as high as possible in order to not miss real cases.

The radiographic reports don't require textual preprocessing however clearly the selection of target_words and skip_words requires reading through reports to get a sense of what vocabulary is being used in the particular dataset that is being evaluated.

Negated terms are identified using Lingua::NegEx which is a perl implementation of Wendy Chapman's NegEx algorithm.

head=2 target_words( \@words );

This is a list of words that describe the clinical entity in question. All forms of the entity in question need to explicitly stated since the package is currently not using lemmatization or stemming.

head=2 skip_words( \@skip );

This is a list of words that can be used to eliminate sentences in the text that might confuse the extractor. For example most radiographic reports start with a brief description of the indication for the test. This statement may state the clinical entity in question but does not mean it is present in the study (ie. Indication: to rule out pulmonary embolism).

=head2 EXPORT

None by default.

=head1 SEE ALSO

This module depends on:

Lingua::NegEx

Text::Sentence

Class::MakeMethods

Also, see http://www.ncbi.nlm.nih.gov/pubmed/21459155 for a similar project using ConText.

=head1 To Do

1. Add lemmatization or stemming to target_words so you don't have to explicitly write out all forms of words.

2. Add ConText support.

=head1 AUTHOR

Eduardo Iturrate, E<lt>ed@iturrate.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Eduardo Iturrate

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
