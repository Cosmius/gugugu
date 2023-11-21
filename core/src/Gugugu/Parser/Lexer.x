{
{-# OPTIONS_HADDOCK hide       #-}
{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-
This lexer is almost a copy from lexer of GHC.
Vide: https://github.com/ghc/ghc/blob/master/compiler/parser/Lexer.x
 -}
module Gugugu.Parser.Lexer
  ( lexToken
  ) where

import           Control.Monad.Except
import           Control.Monad.State
import qualified Data.ByteString      as B
import           Data.List.NonEmpty   (NonEmpty (..), (<|))
import qualified Data.List.NonEmpty   as NonEmpty
import           Data.Map.Strict      (Map)
import qualified Data.Map.Strict      as Map
import           Data.Text            (Text)
import qualified Data.Text            as T
import qualified Data.Text.Encoding   as T
import qualified Data.Vector.Unboxed  as V
import           Data.Word
import           Text.Printf

import           Gugugu.Parser.Types

}

$digit = 0-9
$upper = A-Z
$lower = a-z
$white_no_nl = $white # \n

$alphanumu = [_ $upper $lower $digit]

$pragmachar = [_ $upper]
$non_white = \!-\~

@upperident = $upper $alphanumu*
@lowerident = [_ $lower] $alphanumu*

tokens :-

$white_no_nl+                           ;

"--" .*                                 ;

<bol> {
  \n                                    ;
  ()                                    { doBol }
}

<layout> {
  \n                                    ;
  ()                                    { newLayoutContext }
}

<insertTvRBrace> {
  ()                                    { doInsertTvRBrace }
}

<0> {

  \n                                    { newLexState bol }

  "module"                              { simple TModule }
  "where"                               { simple TWhere }
  "import"                              { simple TImport }
  "data"                                { simple TData }

  "="                                   { simple TEq }
  "|"                                   { simple TVBar }
  ","                                   { simple TComma }
  "::"                                  { simple TDColon }
  "->"                                  { simple TRArrow }

  @upperident                           { simpleString TConId }
  @lowerident                           { simpleString TVarId }

  "{"                                   { simple TLBrace }
  "}"                                   { simple TRBrace }
  "("                                   { simple TLParen }
  ")"                                   { simple TRParen }

  "{-#" $white* $pragmachar+
    / { knownPragma }                   { dispatchPragmas }
}

<prag> {
  \n                                    ;
  "#-}"                                 { simple TPClose }
  $non_white+                           { simpleString TPComp }
}

{

-- | Get next token
lexToken :: P Token
lexToken = do
  PState
    { psAlexStartCodes = sc :| _
    , psInput          = input
    } <- get
  case alexScanUser () input sc of
    AlexEOF                       -> pure TEOF
    AlexSkip newInput _           -> do
      setInput newInput
      lexToken
    AlexToken newInput len action -> do
      setInput newInput
      action input{ pPending = [] } len
    AlexError PInput{..}          -> do
      let fsl = formatSourceLocation pLoc
          msg = printf "%s:\n    Lexical error" fsl
      throwError msg


-- * Alex Actions

--                the input    len    result
type AlexAction = AlexInput -> Int -> P Token

simple :: Token -> AlexAction
simple t _ _ = do
  case t of
    TWhere  -> pushLexState layout
    TPClose -> void popLexState
    _       -> pure ()
  pure t

simpleString :: (Text -> Token) -> AlexAction
simpleString f input len =
  pure . f $ unsafeTakeString len input

doBol :: AlexAction
doBol _ _ = do
  PState{..} <- get
  column <- getColumn
  let n = case psLayoutContext of
        Layout n' : _ -> n'
        _             -> 0
  case column `compare` n of
    LT -> do
      popLayoutContext
      pure TvRBrace
    EQ -> do
      _ <- popLexState
      pure TvSemi
    GT -> do
      _ <- popLexState
      lexToken

newLayoutContext :: AlexAction
newLayoutContext _ _ = do
  _ <- popLexState
  s@PState{..} <- get
  offset <- getColumn
  case psLayoutContext of
    Layout prevOff : _ | offset <= prevOff ->
      pushLexState insertTvRBrace
    _                                      ->
      put s{ psLayoutContext = Layout offset : psLayoutContext }
  pure TvLBrace

doInsertTvRBrace :: AlexAction
doInsertTvRBrace _ _ = do
  _ <- popLexState
  pushLexState bol
  pure TvRBrace

newLexState :: Int -> AlexAction
newLexState n _ _ = do
  pushLexState n
  lexToken


-- Pragmas

knownPragma :: AlexAccPred ()
knownPragma _ input len _ =
  let s = cleanPragma $ unsafeTakeString len input
  in Map.member s pragmas

dispatchPragmas :: AlexAction
dispatchPragmas input len = do
  let s = cleanPragma $ unsafeTakeString len input
  case Map.lookup s pragmas of
    Nothing     -> throwError "unknown pragma"
    Just action -> do
      pushLexState prag
      action input len

pragmas :: Map Text AlexAction
pragmas = Map.fromList
  [ ( "FOREIGN"
    , simple TPForeign
    )
  ]

cleanPragma :: Text -> Text
cleanPragma = T.unwords . drop 1 . T.words


-- Utilities

unsafeTakeString :: Int -> AlexInput -> Text
unsafeTakeString len input =
  let nth i  = Just (V.unsafeIndex src i, i + 1)
      src    = pSrc input
      offset = slOffset . pLoc $ input
  in T.unfoldrN len nth offset

setInput :: AlexInput -> P ()
setInput p = do
  s <- get
  put s
    { psInput = p
    }

getColumn :: P Int
getColumn = gets $ slColumn . pLoc . psInput

pushLexState :: Int -> P ()
pushLexState nsc = do
  ps@PState{..} <- get
  put ps{ psAlexStartCodes = nsc <| psAlexStartCodes }

popLexState :: P Int
popLexState = do
  ps@PState{ psAlexStartCodes = sc :| scs, psInput = PInput{..} } <- get
  case NonEmpty.nonEmpty scs of
    Nothing   ->
      let fsl = formatSourceLocation pLoc
          msg = printf "%s:\n    Alex state expected but nothing available" fsl
      in throwError msg
    Just scs' -> do
      put ps{ psAlexStartCodes = scs' }
      pure sc


-- Definitions required by Alex

type AlexInput = PInput

alexGetByte :: AlexInput -> Maybe (Word8, AlexInput)
alexGetByte p@PInput{ pLoc = loc@SourceLocation{..}, .. } = case pPending of
  b : bs -> Just (b, p{ pPending = bs })
  []     -> if slOffset >= pLen then Nothing else
    let ch        = V.unsafeIndex pSrc slOffset
        newLoc    = moveLoc ch loc
        b :| bs   = charToUtf8Word8s ch
        !newP     = p
          { pLoc      = newLoc
          , pPending  = bs
          , pPrevChar = ch
          }
    in Just (b, newP)

alexInputPrevChar :: AlexInput -> Char
alexInputPrevChar = pPrevChar

moveLoc :: Char -> SourceLocation -> SourceLocation
moveLoc ch loc@SourceLocation{..} = case ch of
  '\t' -> loc
    { slOffset = slOffset + 1
    , slColumn = case slColumn `rem` tabSize of
        0 -> slColumn + tabSize
        _ -> (slColumn `quot` tabSize) + 1
    }
  '\n' -> loc
    { slOffset = slOffset + 1
    , slLine   = slLine + 1
    , slColumn = 1
    }
  _    -> loc
    { slOffset = slOffset + 1
    , slColumn = slColumn + 1
    }

tabSize :: Int
tabSize = 8

charToUtf8Word8s :: Char -> NonEmpty Word8
charToUtf8Word8s = NonEmpty.fromList . B.unpack . T.encodeUtf8 . T.singleton

}
