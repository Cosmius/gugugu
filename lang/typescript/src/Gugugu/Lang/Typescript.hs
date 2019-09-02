{-|
Typescript target
 -}
{-# LANGUAGE ConstraintKinds   #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE StrictData        #-}
module Gugugu.Lang.Typescript
  ( GuguguTsOption(..)
  , makeFiles
  ) where

import           Control.Monad.Except
import           Control.Monad.Reader
import           Data.Foldable
import           Data.List.NonEmpty                 (NonEmpty (..))
import qualified Data.List.NonEmpty                 as NonEmpty
import           Data.Map.Strict                    (Map)
import qualified Data.Map.Strict                    as Map
import           Data.Text                          (Text)
import qualified Data.Text                          as T
import           Data.Traversable
import           System.FilePath

import           Gugugu.Resolver
import           Gugugu.Utilities

import           Gugugu.Lang.Typescript.SourceUtils


-- | Option for 'makeFiles'
data GuguguTsOption
  = GuguguTsOption
    { packagePrefix    :: [Text]                  -- ^ Package prefix
    , withCodec        :: Bool                    -- ^ True if generate codec
    , nameTransformers :: GuguguNameTransformers  -- ^ Name transformers
    }
  deriving Show

-- | Make Typescript AST from 'Module's
makeFiles :: MonadError String m
          => GuguguTsOption
          -> [Module]
          -> m (Map FilePath ImplementationModule)
makeFiles = makeModules


type GuguguK r m = ( MonadError String m
                   , MonadReader r m
                   , HasGuguguTsOption r
                   , HasResolutionContext r
                   )

data GuguguTsEnv
  = GuguguTsEnv
    { gOpts :: GuguguTsOption
    , gCtx  :: ResolutionContext
    }
  deriving Show

class HasGuguguTsOption a where
  toGuguguTsOption :: a -> GuguguTsOption


makeModules :: MonadError String m
            => GuguguTsOption
            -> [Module]
            -> m (Map FilePath ImplementationModule)
makeModules opts modules = do
  let moduleMap = Map.fromList $
        fmap (\md@Module{..} -> (moduleName, md)) modules
  pairs <- for modules $ \md@Module{..} -> do
    let rCtx = ResolutionContext
          { rcModules       = moduleMap
          , rcCurrentModule = md
          }
        env  = GuguguTsEnv
          { gOpts = opts
          , gCtx  = rCtx
          }
    runReaderT (makeModule md) env
  pure $ Map.fromList pairs

makeModule :: GuguguK r m => Module -> m (FilePath, ImplementationModule)
makeModule md@Module{..} = do
  GuguguTsOption{..} <- asks toGuguguTsOption
  typeDecs <- traverse makeData moduleDatas
  tsModule <- mkTypescriptModule md
  let importPrefix = if depth > 0
        then T.intercalate "/" $ replicate depth ".."
        else "."
        where depth = length tsModule - 1
  let imports' = []
  let moduleBody = ImplementationModule
        { imImports = imports
        , imBody    = concat typeDecs
        }
      path       = tsModulePath tsModule <> ".ts"
      imports    =
          f withCodec guguguCodecAlias "codec"
        $ imports'
        where f cond alias m = if cond
                then ((alias, importPrefix <> "/gugugu/" <> m) :)
                else id
  pure (path, moduleBody)

makeData :: GuguguK r m => Data -> m [ImplementationModuleElement]
makeData d@Data{..} = do
  GuguguTsOption{..} <- asks toGuguguTsOption
  dataCode <- mkTypeCode d
  dec <- case dataConDef of
    DRecord RecordCon{..} -> do
      params <- for recordConFields $ \rf@RecordField{..} -> do
        tsType <- makeType recordFieldType
        fieldCode <- mkFieldCode rf
        pure Parameter
          { pModifiers = [MPublic]
          , pName      = fieldCode
          , pType      = tsType
          }
      let classDec = ClassDeclaration
            { cdModifiers = [MExport]
            , cdName      = dataCode
            , cdBody      = [CEC classCon]
            }
          classCon = ConstructorDeclaration
            { ccdModifiers = [MPublic]
            , ccdParams    = params
            }
      pure $ MEC classDec

  codecDefs <- if withCodec then makeCodecDefs d else pure []

  let decs = if null codecDefs
        then [dec]
        else case dec of
          MEC classDec ->
            let newDec = classDec
                  { cdBody = cdBody classDec <> fmap CEV codecDefs
                  }
            in [MEC newDec]
  pure decs

makeCodecDefs :: GuguguK r m => Data -> m [MemberVariableDeclaration]
makeCodecDefs d@Data{..} = do
  dataCode <- mkTypeCode d
  let eImpl           = ESimple "impl"
      encoderTypeName = codecPkgId "Encoder"
      decoderTypeName = codecPkgId "Decoder"
      eS              = ESimple "s"
      eA              = ESimple "a"
      -- typescript type of this type
      tThis           = tSimple dataCode
      codecPkgId n    = NamespaceName $ guguguCodecAlias :| [n]
  (encodeFDef, decodeFDef) <- case dataConDef of
    DRecord RecordCon{..} -> do
      let eEncodeRecordField = eImpl `EMember` "encodeRecordField"
          eDecodeRecordField = eImpl `EMember` "decodeRecordField"
          eS0                = ESimple "s0"
      codecComps <- for (indexed recordConFields) $ \(i, rf) -> do
        (encoderExpr, decoderExpr) <- makeCodecExpr $ recordFieldType rf
        fieldCode <- mkFieldCode rf
        fieldValue <- mkFieldValue rf
        let encodeDef  = LexicalDeclaration
              { ldModifiers = []
              , ldPattern   = PSimple sn
              , ldDef       = ECall eEncodeRecordField []
                  [ eSPrevious, eI, fieldValue
                  , EArrow ArrowFunction
                      { afParams = ["s0"]
                      , afBody   = Left $ ECall encoderExpr []
                          [eS0, eA `EMember` fieldCode, eImpl]
                      }
                  ]
              }
            decodeDef  = LexicalDeclaration
              { ldModifiers = []
              , ldPattern   = PArray [sn, vn]
              , ldDef       = ECall eDecodeRecordField []
                  [ eSPrevious, eI, fieldValue
                  , EArrow ArrowFunction
                      { afParams = ["s0"]
                      , afBody   = Left $ ECall decoderExpr []
                          [eS0, eImpl]
                      }
                  ]
              }
            eN         = ESimple vn
            eI         = ESimple $ showText i
            eSPrevious = ESimple $ "s" <> showText (i + 1)
            sn         = "s" <> showText (i + 2)
            vn         = "v" <> showText i
        pure (SID encodeDef, SID decodeDef, eN)
      let (encodeDefs, decodeDefs, fieldNames) = unzip3 codecComps
      let encodeFDef = ECall (eImpl `EMember` "encodeRecord") []
            [eS, eN, eArrow1 "s1" (Right $ encodeDefs <> [SIR eSl])]
          decodeFDef = ECall (eImpl `EMember` "decodeRecord") []
            [eS, eN, eArrow1 "s1" (Right $ decodeDefs <> [SIR eR])]
            where eR = EArray [eSl, ENew (ESimple dataCode) fieldNames]
          eN         = ESimple $ showText nFields
          -- last s
          eSl        = ESimple $ "s" <> showText (nFields + 1)
          nFields    = length recordConFields
      pure (encodeFDef, decodeFDef)
  let encoderDef = MemberVariableDeclaration
        { mvdModifiers = [MPublic, MStatic]
        , mvdName      = "encode" <> dataCode
        , mvdType      = TParamed encoderTypeName [tThis]
        , mvdDef       = EArrow encodeDef
        }
      decoderDef = MemberVariableDeclaration
        { mvdModifiers = [MPublic, MStatic]
        , mvdName      = "decode" <> dataCode
        , mvdType      = TParamed decoderTypeName [tThis]
        , mvdDef       = EArrow decodeDef
        }
      encodeDef = ArrowFunction
        { afParams = ["s", "a", "impl"]
        , afBody   = Left encodeFDef
        }
      decodeDef = ArrowFunction
        { afParams = ["s", "impl"]
        , afBody   = Left decodeFDef
        }
  pure [encoderDef, decoderDef]

makeType :: GuguguK r m => GType -> m Type
makeType GApp{..} = do
  tFirst <- resolveTsType typeCon
  params <- traverse makeType typeParams
  case tFirst of
    Right t     -> pure $ TParamed t params
    Left TMaybe -> case params of
      [p] -> pure $ TUnion $ tSimple "null" :| [p]
      _   -> throwError "Maybe type requires exactly one parameter"

makeCodecExpr :: GuguguK r m => GType -> m (Expression, Expression)
makeCodecExpr GApp{..} = do
  codec@(encoderF, decoderF) <- resolveTypeCodec typeCon
  params <- traverse makeCodecExpr typeParams
  pure $ case params of
    [] -> codec
    _  -> let (encoderPs, decoderPs) = unzip params
          in (ECall encoderF [] encoderPs, ECall decoderF [] decoderPs)


resolveTsType :: GuguguK r m => Text -> m (Either TSpecial NamespaceName)
resolveTsType t = do
  rr <- resolveTypeCon t
  case rr of
    ResolutionError e -> throwError e
    LocalType d       -> do
      typeName <- mkTypeCode d
      pure . Right $ nSimple typeName
    Primitive pt      -> case pt of
      PUnit   -> pure . Right $ nSimple "{}"
      PBool   -> pure . Right $ nSimple "boolean"
      PInt32  -> pure . Right $ nSimple "number"
      PDouble -> pure . Right $ nSimple "number"
      PString -> pure . Right $ nSimple "string"
      PMaybe  -> pure $ Left TMaybe
      PList   -> pure . Right $ nSimple "Array"

data TSpecial
  = TMaybe
  deriving Show

resolveTypeCodec :: GuguguK r m => Text -> m (Expression, Expression)
resolveTypeCodec t = do
  rr <- resolveTypeCon t
  case rr of
    ResolutionError e -> throwError e
    LocalType d       -> do
      typeName <- mkTypeCode d
      let f p = EMember (ESimple typeName) $ p <> typeName
      pure (f "encode", f "decode")
    Primitive _       ->
      let f ct = ESimple guguguCodecAlias `EMember` ct `EMember` T.toLower t
      in pure (f "Encoder", f "Decoder")

tsModulePath :: NonEmpty Text -> FilePath
tsModulePath (part1 :| parts) = foldl' (\z x -> z </> T.unpack x)
                                       (T.unpack part1)
                                       parts


-- Name transformers

mkTypescriptModule :: GuguguK r m => Module -> m (NonEmpty Text)
mkTypescriptModule Module{..} = do
  GuguguTsOption{..} <- asks toGuguguTsOption
  withTransformer transModuleCode $ \f ->
    NonEmpty.fromList $ packagePrefix <> [f moduleName]

mkTypeCode :: GuguguK r m => Data -> m Text
mkTypeCode Data{..} = withTransformer transTypeCode $ \f ->
  f dataName

mkFieldCode :: GuguguK r m => RecordField -> m Text
mkFieldCode RecordField{..} = withTransformer transFieldCode $ \f ->
  f recordFieldName

mkFieldValue :: GuguguK r m => RecordField -> m Expression
mkFieldValue RecordField{..} = withTransformer transFieldValue $ \f ->
  ESimple $ unsafeQuote $ f recordFieldName


-- Utilities

guguguCodecAlias :: Text
guguguCodecAlias = "_gugugu_c"

nSimple :: Text -> NamespaceName
nSimple t = NamespaceName $ t :| []

eArrow1 :: Text -> Either Expression FunctionBody -> Expression
eArrow1 t body = EArrow ArrowFunction
  { afParams = [t]
  , afBody   = body
  }

tSimple :: Text -> Type
tSimple t = TParamed (nSimple t) []

withTransformer :: GuguguK r m
                => (GuguguNameTransformers -> NameTransformer)
                -> ((Text -> Text) -> a)
                -> m a
withTransformer selector k = do
  nt <- asks $ selector . nameTransformers . toGuguguTsOption
  pure . k $ runNameTransformer nt


-- Instances

instance HasGuguguTsOption GuguguTsEnv where
  toGuguguTsOption = gOpts

instance HasResolutionContext GuguguTsEnv where
  toResolutionContext = gCtx
