package Lingua::DxExtractor;

use 5.008008;
use strict;
use warnings;

our $VERSION = '0.01';

use Class::MakeMethods (
  'Standard::Global:object' => 'pipeline',

  'Template::Hash:scalar' => [
        'orig_text', 'final_answer', 'ambiguous',
  ],
  'Template::Hash:hash' => [
        'target_sentences',
  ],
  'Template::Hash:array' => [
        'words', 'skip_words'
  ],
  'Template::Hash:object' => [
    {
        name=> 'results',
        class=> 'Lingua::StanfordCoreNLP::PipelineSentenceList'
    },
  ],
);

use Lingua::StanfordCoreNLP;
Inline->init();
Lingua::DxExtractor->pipeline( Lingua::StanfordCoreNLP::Pipeline->new );

######################################################################

# $extractor = Lingua::DxExtractor->new( { words => $words, skip_words => $skip_words } );
sub new {
  my $callee = shift;
  my $package = ref $callee || $callee;
  my $self = shift;
  bless $self, $package;
  die unless $self->words;
  return $self;
}

sub process_text {
  my ($self,$text) = @_;
  $self->orig_text( $text ) unless $self->orig_text;
  my $results = $self->pipeline->process($text);
  $self->results( $results );
}

sub examine_text {
   my $self = shift;
   return unless my $results = $self->results;

   for my $sentence ( @{$results->toArray} ) {
     next if grep { $sentence->getSentence =~ /$_/i } @{$self->skip_words};

     my ($no_determiner, $without, $negation_modifier, $word_holder );

     # loop through POS tagged words
     my $pos;
     for my $token (@{$sentence->getTokens->toArray}) {
       $pos .=  sprintf "\t%s/%s/%s [%s]\n",
              $token->getWord,
              $token->getPOSTag,
              $token->getNERTag,
              $token->getLemma;

       if ( grep { $token->getLemma eq $_ } @{$self->words} ) {
         $self->target_sentences->{ $sentence->getIDString }->{word}->{ $token->getLemma } = 'present';
         $self->target_sentences->{ $sentence->getIDString }->{orig} = $sentence->getSentence;
       }
     }
     $self->target_sentences->{ $sentence->getIDString }->{pos} = $pos
        if $self->target_sentences->{ $sentence->getIDString }->{word};

     # loop through dependencies
     next unless $self->target_sentences->{ $sentence->getIDString }->{word};

     my $d;
     for my $dep (@{$sentence->getDependencies->toArray}) {
       $d .= sprintf "\t%s(%s-%d, %s-%d) [%s]\n",
          $dep->getRelation,
          $dep->getGovernor->getWord,
          $dep->getGovernorIndex,
          $dep->getDependent->getWord,
          $dep->getDependentIndex,
          $dep->getLongRelation;

       $word_holder->{ $dep->getGovernor->getLemma } ++;
       $word_holder->{ $dep->getDependent->getLemma } ++;

       if ( $no_determiner ) {
         $no_determiner->{ $dep->getGovernor->getLemma } ++;
         $no_determiner->{ $dep->getDependent->getLemma } ++;
       }
       if ( $without ) {
         $without->{ $dep->getGovernor->getLemma } ++;
         $without->{ $dep->getDependent->getLemma } ++;
       }
       if ( ($dep->getLongRelation eq 'determiner' || $dep->getLongRelation eq 'dependent') && $dep->getDependent->getLemma eq 'no' ) {
         $no_determiner->{ $dep->getGovernor->getLemma } ++;
       } elsif ( $dep->getRelation =~ /without/ ) {
         $without->{ $dep->getGovernor->getLemma  } ++;
         $without->{ $dep->getDependent->getLemma  } ++;
       } elsif ( $dep->getLongRelation =~ /negation/ ) {
         $negation_modifier++;
       }

     }
     $self->target_sentences->{ $sentence->getIDString }->{dep} = $d;

     if ( $no_determiner ) {
       foreach my $term ( keys %$no_determiner ) {
         next unless grep { $_ eq $term } @{$self->words};
         $self->target_sentences->{ $sentence->getIDString }->{word}->{ $term } = 'absent';
       }
     }

     if ( $without ) {
       foreach my $term ( keys %$without ) {
         next unless grep { $_ eq $term } @{$self->words};
         $self->target_sentences->{ $sentence->getIDString }->{word}->{ $term } = 'absent';
       }
     }

     if ( $negation_modifier ) {
       foreach my $term ( keys %$word_holder ) {
         next unless grep { $_ eq $term } @{$self->words};
         $self->target_sentences->{ $sentence->getIDString }->{word}->{ $term } = 'absent';
       }
     }
   }
}

# my $debug_info = $extractor->finalize_results;
sub finalize_results {
  my $self = shift;
  my $out;
  #$out = "TEXT: " . $self->orig_text . "\n";

  my $final_answer;
  my $ambiguous = 0;
  my $answers;

  foreach my $sid ( keys %{$self->target_sentences} ) {
    next unless $self->target_sentences->{$sid}->{orig};

    $out .= "($sid)\n" . $self->target_sentences->{ $sid }->{orig} . "\n";
    $out .= "POS: " . $self->target_sentences->{ $sid }->{pos} . "\n";
    $out .= "Dep: " . $self->target_sentences->{ $sid }->{dep} . "\n";
    foreach my $word ( keys %{ $self->target_sentences->{ $sid }->{word} }   ) {
      $out .= "$word is " . $self->target_sentences->{ $sid }->{word}->{ $word } . "\n";

      $ambiguous = 1 if $final_answer &&
        $final_answer ne $self->target_sentences->{ $sid }->{word}->{ $word };
      $final_answer = $self->target_sentences->{ $sid }->{word}->{ $word };
      $answers->{ $self->target_sentences->{ $sid }->{word}->{ $word } }++;
    }
    $out .= "\n";
  }
  if ( $ambiguous ) {
    my $count = 0;
    my $a = $answers->{ absent };
    my $p = $answers->{ present };
    if ( $a > $p ) {
      $final_answer = 'absent';
    } elsif ( $p > $a ) {
      $final_answer = 'present';
    } else {
      $final_answer = 'present';
    }
  }
  $final_answer ||= 'absent';

  $self->final_answer( $final_answer );
  $self->ambiguous( $ambiguous );

  return $out;
}


sub reset {
  my $self = shift;
  $self->orig_text( '' );
  $self->results->clear if $self->results;
  $self->target_sentences( {} );
}


1;
__END__

=head1 NAME

Lingua::DxExtractor - Perl extension to perform named entity recognition and some degree of looking for negation in a quick and dirty way relying on StanfordCoreNLP. 

=head1 SYNOPSIS

  use Lingua::DxExtractor;

  my $extractor = Lingua::DxExtractor->new( {
    words => [  qw( embolus embolism pe clot thromboembolism defect ) ],
    skip_words => [ qw( evaluate evaluation history indication technique assessment nondiagnostic uninterpretable ) ],
  } );

  my $counter ;
  $extractor->process_text( $text );
  $extractor->examine_text;

  $debug =  $extractor->finalize_results;
  $absent_or_present = $extractor->final_answer;
  $is_final_answer_ambiguous = $extractor->ambiguous;

=head1 DESCRIPTION

A quick and dirty NER tool to be used to find diagnostic entities within clinical text. It also includes a simple attempt at finding negated terms. The extractor gives a 'final answer', 'absent' or 'present'. Also the extractor reports if it isn't sure and the answer is ambiguous. 

The 'use case' for this is when performing a research project with a large number of records and you need to identify a subset based on a diagnostic entity, you can use this tools to reduce the number of charts that have to be manually examined. In this 'use case' I wanted to keep the sensitivity as high as possible in order to not miss real cases.


=head2 EXPORT

None by default.

=head1 SEE ALSO

This module depends on:

Lingua::StanfordCoreNLP which in turn depends on Inline::Java


=head1 AUTHOR

Iturrate, E<lt>ed@iturrate.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Eduardo Iturrate 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
