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

import           Control.Applicative
import           Control.Monad.Except
import           Control.Monad.Reader
import           Data.Bifunctor
import           Data.Foldable
import           Data.List
import           Data.List.NonEmpty                 (NonEmpty (..))
import qualified Data.List.NonEmpty                 as NonEmpty
import           Data.Map.Strict                    (Map)
import qualified Data.Map.Strict                    as Map
import           Data.Set                           (Set)
import qualified Data.Set                           as Set
import           Data.Text                          (Text)
import qualified Data.Text                          as T
import           Data.Traversable
import           Data.Tuple
import           System.FilePath
import           Text.Printf

import           Gugugu.Resolver
import           Gugugu.Utilities

import           Gugugu.Lang.Typescript.SourceUtils


-- | Option for 'makeFiles'
data GuguguTsOption
  = GuguguTsOption
    { packagePrefix    :: [Text]                  -- ^ Package prefix
    , withCodec        :: Bool                    -- ^ True if generate codec
    , withServer       :: Bool                    -- ^ True if generate server
    , withClient       :: Bool                    -- ^ True if generate client
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
makeModules opts@GuguguTsOption{..} modules = do
  let moduleMap = Map.fromList $
        fmap (\md@Module{..} -> (moduleName, md)) modules
  foreignCodecPartsAndfiles <- for modules $ \md -> do
    let rCtx = ResolutionContext
          { rcModules       = moduleMap
          , rcCurrentModule = md
          }
        env  = GuguguTsEnv
          { gOpts = opts
          , gCtx  = rCtx
          }
    runReaderT (makeModule md) env
  let (foreignCodecParts, pairs) = unzip foreignCodecPartsAndfiles
  let (foreignImports, (encodeImpls, decodeImpls)) = fold foreignCodecParts
  let allFiles            = if withCodec
        then filesWithoutForeign <> foreignCodecs else filesWithoutForeign
      filesWithoutForeign = Map.fromList pairs
      foreignCodecs       = Map.singleton "gugugu/foreign-codecs.ts"
        ImplementationModule
          { imImports = toList foreignImports
          , imBody    =
              [ f "ForeignEncodersImpl" encodeImpls
              , f "ForeignDecodersImpl" decodeImpls
              ]
          }
        where
          f name methods = MEI InterfaceDeclaration
            { idModifiers = [MExport]
            , idName      = name
            , idTParams   = ["S"]
            , idMethods   = methods
            }
  pure allFiles

type ForeignTypeResult
  = (Set ImportItem, ([MethodSignature], [MethodSignature]))

makeModule :: GuguguK r m
           => Module
           -> m (ForeignTypeResult, (FilePath, ImplementationModule))
makeModule md@Module{..} = do
  GuguguTsOption{..} <- asks toGuguguTsOption
  moduleMap <- asks $ rcModules . toResolutionContext
  foreignCodecPartsAndtypeDecs <- traverse (makeData md) moduleDatas
  let (foreignCodecParts, typeDecs) = unzip foreignCodecPartsAndtypeDecs
  let foreignCodecMerged@(foreignImports, _) = fold foreignCodecParts
  transportElems <- if (withServer || withClient) && not (null moduleFuncs)
    then makeTransport md
    else pure []
  tsModule <- mkTypescriptModule md
  let importPrefix = if depth > 0
        then T.intercalate "/" $ replicate depth ".."
        else "."
        where depth = length tsModule - 1
  imports' <- for moduleImports $ \name -> do
    importedMd <- case Map.lookup name moduleMap of
      Just v  -> pure v
      Nothing -> throwError $ printf "cannot resolve module: %s" name
    importedMdName <- mkTypescriptModule importedMd
    importAlias <- mkGuguguImportAlias importedMd
    let importPath  = importPrefix <> "/"
                   <> T.intercalate "/" (toList importedMdName)
    pure (importAlias, importPath)
  let moduleBody = ImplementationModule
        { imImports = imports
        , imBody    = concat typeDecs <> transportElems
        }
      path       = tsModulePath tsModule <> ".ts"
      imports    =
          f withCodec guguguCodecAlias "codec"
        . f (withServer || withClient) guguguTransportAlias "transport"
        . (if withCodec then (toList foreignImports ++) else id)
        $ imports'
        where f cond alias m = if cond
                then ((alias, importPrefix <> "/gugugu/" <> m) :)
                else id
  pure (foreignCodecMerged, (path, moduleBody))

makeData :: GuguguK r m
         => Module
         -> Data
         -> m (ForeignTypeResult, [ImplementationModuleElement])
makeData md d@Data{..} = do
  GuguguTsOption{..} <- asks toGuguguTsOption
  dataCode <- mkTypeCode d
  dec <- case dataConDef of
    Just (DRecord RecordCon{..}) -> do
      params <- for recordConFields $ \rf@RecordField{..} -> do
        tsType <- makeType recordFieldType
        fieldCode <- mkFieldCode rf
        pure Parameter
          { pModifiers = [MPublic]
          , pName      = fieldCode
          , pOptional  = False
          , pType      = tsType
          }
      let classDec = ClassDeclaration
            { cdModifiers = [MExport]
            , cdName      = dataCode
            , cdTParams   = []
            , cdImpls     = []
            , cdBody      = [CEC classCon]
            }
          classCon = ConstructorDeclaration
            { ccdModifiers = [MPublic]
            , ccdParams    = params
            }
      pure $ MEC classDec
    Just (DEnum names)           -> do
      enums <- traverse mkEnumCode names
      let typeDec = TypeAliasDeclaration
            { tadModifiers = [MExport]
            , tadName      = dataCode
            , tadType      = TUnion $ tSimple <$> enums
            }
      pure $ MET typeDec
    Nothing                      -> do
      (_, name) <- resolveForeign' d
      let typeDec = TypeAliasDeclaration
            { tadModifiers = [MExport]
            , tadName      = dataCode
            , tadType      = TParamed name []
            }
      pure $ MET typeDec

  (foreigns, codecDefs) <- if withCodec
    then makeCodecDefs md d else pure mempty

  let decs = if null codecDefs
        then [dec]
        else case dec of
          MEC classDec ->
            let newDec = classDec
                  { cdBody = cdBody classDec <> fmap CEV codecDefs
                  }
            in [MEC newDec]
          _                     ->
            let codecClsDec = MEC ClassDeclaration
                  { cdModifiers = []
                  , cdName      = name
                  , cdTParams   = []
                  , cdImpls     = []
                  , cdBody      = fmap CEV codecDefs
                  }
                aliasDec    = MED LexicalDeclaration
                  { ldModifiers = [MExport]
                  , ldPattern   = PSimple dataCode
                  , ldDef       = ESimple name
                  }
                name        = "_" <> dataCode
            in [dec, codecClsDec, aliasDec]
  pure (foreigns, decs)

makeCodecDefs :: GuguguK r m
              => Module
              -> Data
              -> m (ForeignTypeResult, [MemberVariableDeclaration])
makeCodecDefs md d@Data{..} = do
  dataCode <- mkTypeCode d
  let eImpl           = ESimple "impl"
      encoderTypeName = codecPkgId "Encoder"
      decoderTypeName = codecPkgId "Decoder"
      eS              = ESimple "s"
      eA              = ESimple "a"
      -- typescript type of this type
      tThis           = tSimple dataCode
      codecPkgId n    = NamespaceName $ guguguCodecAlias :| [n]
  (foreignCodecs, encodeFDef, decodeFDef) <- case dataConDef of
    Just (DRecord RecordCon{..}) -> do
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
      pure (mempty, encodeFDef, decodeFDef)
    Just (DEnum names)           -> do
      decodeCases <- for (indexed $ toList names) $ \(i, name) -> do
        enumCode <- mkEnumCode name
        enumValue <- mkEnumValue name
        let encoded = (ESimple $ showText i, enumValue)
            decoded = ESimple enumCode
        pure (encoded, decoded)
      let encodeCases = fmap swap decodeCases
      let encodeFDef  = ECall (eImpl `EMember` "encodeEnum") [tThis]
            [eS, eA, fSwitchE fst, fSwitchE snd]
            where
              fSwitchE selector = eArrow1 "a0" $ Right
                [ SSwitch eA0 $
                    fmap (second $ (: []) . SIR . selector) encodeCases
                ]
              eA0               = ESimple "a0"
          decodeFDef  = ECall (eImpl `EMember` "decodeEnum") [tThis]
            [eS, fSwitchD "i" fst, fSwitchD "n" snd]
            where
              fSwitchD arg selector = eArrow1 arg $ Right
                [ SSwitch (ESimple arg) $
                    fmap (first selector . second ((: []) . SIR)) decodeCases
                , SIR $ ESimple "null"
                ]
      pure (mempty, encodeFDef, decodeFDef)
    Nothing                      -> do
      (importItem, tsThisName) <- resolveForeign' d
      (encodeF, decodeF) <- mkForeignCodecName md d
      let encodeImpl         = MethodSignature
            { msName    = encodeF
            , msTParams = []
            , msParams  =
                [ pS
                , Parameter
                    { pModifiers = []
                    , pName      = "a"
                    , pOptional  = False
                    , pType      = tsThis
                    }
                ]
            , msRType   = tS
            }
          decodeImpl         = MethodSignature
            { msName    = decodeF
            , msTParams = []
            , msParams  = [pS]
            , msRType   = TArray [tS, tsThis]
            }
          encodeFDef         = ECall (eImpl `EMember` encodeF) [] [eS, eA]
          decodeFDef         = ECall (eImpl `EMember` decodeF) [] [eS]
          tsThis             = TParamed tsThisName []
          pS                 = Parameter
            { pModifiers = []
            , pName      = "s"
            , pOptional  = False
            , pType      = tS
            }
          tS                 = tSimple "S"
      pure ( (Set.singleton importItem, ([encodeImpl], [decodeImpl]))
           , encodeFDef, decodeFDef
           )
  encoderName <- mkTypeFunc $ "encode" <> dataName
  decoderName <- mkTypeFunc $ "decode" <> dataName
  let encoderDef = MemberVariableDeclaration
        { mvdModifiers = [MPublic, MStatic]
        , mvdName      = encoderName
        , mvdType      = TParamed encoderTypeName [tThis]
        , mvdDef       = EArrow encodeDef
        }
      decoderDef = MemberVariableDeclaration
        { mvdModifiers = [MPublic, MStatic]
        , mvdName      = decoderName
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
  pure (foreignCodecs, [encoderDef, decoderDef])

makeTransport :: GuguguK r m => Module -> m [ImplementationModuleElement]
makeTransport md@Module{..} = do
  GuguguTsOption{..} <- asks toGuguguTsOption
  let eEncode              = ESimple guguguCodecAlias
        `EMember` "Encoder" `EMember` "encode"
      eDecode              = ESimple guguguCodecAlias
        `EMember` "Decoder" `EMember` "decode"
      tI                   = tSimple "I"
      tO                   = tSimple "O"
      codecPkgId t         = NamespaceName $ guguguCodecAlias :| [t]
      eNamespace           = ESimple "namespace"
      transportPkgId t     = NamespaceName $ guguguTransportAlias :| [t]
      eK                   = ESimple "k"
      eImpl                = ESimple "impl"
      eTransportSend       = ESimple "transport" `EMember` "send"
      eFa                  = EObject
        [ PDProperty "data" $ ESimple "a"
        , PDProperty "meta" $ ESimple "meta"
        ]
      eFEncode arg encoder = eArrow1 arg $ Left $ ECall eEncode []
        [ESimple arg, eEncoderImpl, encoder]
      eFDecode arg decoder = eArrow1 arg $ Left $ ECall eDecode []
        [ESimple arg, eDecoderImpl, decoder]
      eEncoderImpl         = ESimple "encoderImpl"
      eDecoderImpl         = ESimple "decoderImpl"
      tSRA                 = [tSimple "SA", tSimple "RA"]
      tSRB                 = [tSimple "SB", tSimple "RB"]
  transportComps <- for moduleFuncs $ \fn@Func{..} -> do
    fd <- makeType funcDomain
    funcCodomain1 <- case funcCodomain of
      GApp{ typeCon = "IO", typeParams = [v] } -> pure v
      _                                        ->
        throwError "Function codomain must be a type like IO a"
    fcd <- makeType funcCodomain1
    (fdEncoder, fdDecoder) <- makeCodecExpr funcDomain
    (fcdEncoder, fcdDecoder) <- makeCodecExpr funcCodomain1
    funcCode <- mkFuncCode fn
    funcValue <- mkFuncValue fn
    let serverFDec = iDec False
        clientFDec = iDec True
        serverExpr = EArrow ArrowFunction
          { afParams = ["fr"]
          , afBody   = Left $ ECall eK [fd, fcd]
              [ ESimple "fr"
              , eFDecode "r" fdDecoder
              , eFEncode "b1" fcdEncoder
              , eArrow1 "fa" $ Left $ ECall
                (eImpl `EMember` funcCode)
                []
                [eFa' `EMember` "data", eFa' `EMember` "meta"]
              ]
          }
          where eFa' = ESimple "fa"
        clientFDef = PDMethod clientFDec
          [ SIR $ ECall eTransportSend []
              [ EObject
                  [ PDProperty "namespace" eNamespace
                  , PDProperty "name" funcValue
                  ]
              , eFa
              , eFEncode "a1" fdEncoder
              , eFDecode "r" fcdDecoder
              ]
          ]
        iDec x     = MethodSignature
          { msName    = funcCode
          , msTParams = []
          , msParams  =
              [ Parameter
                  { pModifiers = []
                  , pName      = "a"
                  , pOptional  = False
                  , pType      = fd
                  }
              , Parameter
                  { pModifiers = []
                  , pName      = "meta"
                  , pOptional  = x
                  , pType      = tI
                  }
              ]
          , msRType   = TParamed (nSimple "Promise")
              [ TParamed (transportPkgId "WithMeta") [tO, fcd]
              ]
          }
    pure (serverFDec, (funcValue, [SIR serverExpr]), clientFDec, clientFDef)
  let (serverFDecs, serverCases, clientFDecs, clientFDefs) =
        unzip4 transportComps
  moduleValue <- mkModuleValue md
  serverIName <- mkModuleType md "Server"
  clientIName <- mkModuleType md "Client"
  let serverDecs   = if withServer then serverDecs' else []
        where serverDecs' = [serverIDec, serverCDec, lServer]
      clientDecs   = if withClient then clientDecs' else []
        where clientDecs' = [clientIDec, clientCDec, lClient]
      serverIDec   = MEI InterfaceDeclaration
        { idModifiers = [MExport]
        , idName      = serverIName
        , idTParams   = iParams
        , idMethods   = serverFDecs
        }
      clientIDec   = MEI InterfaceDeclaration
        { idModifiers = [MExport]
        , idName      = clientIName
        , idTParams   = iParams
        , idMethods   = clientFDecs
        }
      serverCDec   = MEC ClassDeclaration
        { cdModifiers = []
        , cdName      = serverCName
        , cdTParams   = []
        , cdImpls     = []
        , cdBody      =
            [ CEM MemberFunctionDeclaration
                { mfdModifiers = [MPublic, MStatic]
                , mfdSig       = MethodSignature
                    { msName    = "toTransport"
                    , msTParams = fParams
                    , msParams  =
                        [ Parameter
                            { pModifiers = []
                            , pName      = "impl"
                            , pOptional  = False
                            , pType      = tServerI
                            }
                        , Parameter
                            { pModifiers = []
                            , pName      = "decoderImpl"
                            , pOptional  = False
                            , pType      = TParamed
                                (codecPkgId "DecoderImpl") tSRA
                            }
                        , Parameter
                            { pModifiers = []
                            , pName      = "encoderImpl"
                            , pOptional  = False
                            , pType      = TParamed
                                (codecPkgId "EncoderImpl") tSRB
                            }
                        ]
                    , msRType   = TParamed
                        (transportPkgId "ServerTransport")
                        (fmap tSimple tParams)
                    }
                , mfdBody      = [SIR $ EObject [PDMethod askSig askBody]]
                }
            ]
        }
        where
          askSig  = MethodSignature
            { msName    = "ask"
            , msTParams = []
            , msParams  =
                [ Parameter
                    { pModifiers = []
                    , pName      = "name"
                    , pOptional  = False
                    , pType      = TParamed (transportPkgId "QualName") []
                    }
                , Parameter
                    { pModifiers = []
                    , pName      = "k"
                    , pOptional  = False
                    , pType      = TParamed
                        (transportPkgId "ServerCodecHandler")
                        (fmap tSimple tParams)
                    }
                ]
            , msRType   = TUnion $ tSimple "null" :|
                [ TParen $ TFunc []
                    [ Parameter
                        { pModifiers = []
                        , pName      = "fa"
                        , pOptional  = False
                        , pType      = TParamed
                            (transportPkgId "WithMeta")
                            [tI, tSimple "RA"]
                        }
                    ] $ TParamed (nSimple "Promise")
                      [ TParamed (transportPkgId "WithMeta")
                          [ TUnion $ tSimple "undefined" :| [tO]
                          , tSimple "RB"
                          ]
                      ]
                ]
            }
          askBody = [ SIf cond (SIR $ ESimple "null") Nothing
                    , SSwitch (eName `EMember` "name") serverCases
                    , SIR $ ESimple "null"
                    ]
          cond    = EBinary cLen "||" cVal
          cLen    = eLen eNNs `eNeq` eLen eNamespace
          cVal    = ECall
            (eNNs `EMember` "some")
            []
            [ EArrow ArrowFunction
                { afParams = ["v", "i"]
                , afBody   = Left $
                    (eNamespace `EIndex` ESimple "i") `eNeq` ESimple "v"
                }
            ]
          eName   = ESimple "name"
          eNNs    = eName `EMember` "namespace"
          eLen e  = e `EMember` "length"
      clientCDec   = MEC ClassDeclaration
        { cdModifiers = []
        , cdName      = clientCName
        , cdTParams   = []
        , cdImpls     = []
        , cdBody      =
            [ CEM MemberFunctionDeclaration
                { mfdModifiers = [MPublic, MStatic]
                , mfdSig       = MethodSignature
                    { msName    = "fromTransport"
                    , msTParams = fParams
                    , msParams  =
                        [ Parameter
                            { pModifiers = []
                            , pName      = "transport"
                            , pOptional  = False
                            , pType      = TParamed
                                (transportPkgId "ClientTransport")
                                (fmap tSimple tParams)
                            }
                        , Parameter
                            { pModifiers = []
                            , pName      = "encoderImpl"
                            , pOptional  = False
                            , pType      = TParamed
                                (codecPkgId "EncoderImpl") tSRA
                            }
                        , Parameter
                            { pModifiers = []
                            , pName      = "decoderImpl"
                            , pOptional  = False
                            , pType      = TParamed
                                (codecPkgId "DecoderImpl") tSRB
                            }
                        ]
                    , msRType   = tClientI
                    }
                , mfdBody      = [SIR $ EObject clientFDefs]
                }
            ]
        }
      lServer      = MED LexicalDeclaration
        { ldModifiers = [MExport]
        , ldPattern   = PSimple serverIName
        , ldDef       = ESimple serverCName
        }
      lClient      = MED LexicalDeclaration
        { ldModifiers = [MExport]
        , ldPattern   = PSimple clientIName
        , ldDef       = ESimple clientCName
        }
      namespaceDec = MED LexicalDeclaration
        { ldModifiers = [MExport]
        , ldPattern   = PSimple "namespace"
        , ldDef       = moduleValue
        }

      tServerI     = TParamed (nSimple serverIName) $ fmap tSimple iParams
      tClientI     = TParamed (nSimple clientIName) $ fmap tSimple iParams

      serverCName  = "_" <> serverIName
      clientCName  = "_" <> clientIName
      iParams      = ["I", "O"]
      tParams      = ["I", "O", "RA", "RB"]
      fParams      = ["I", "O", "RA", "RB", "SA", "SB"]

  pure $ serverDecs <> clientDecs <> [namespaceDec]


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
    Imported md d     -> do
      typeName <- mkTypeCode d
      importAlias <- mkGuguguImportAlias md
      pure . Right . NamespaceName $ importAlias :| [typeName]
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
      let f p = do
            funcName <- mkTypeFunc $ p <> dataName d
            pure $ EMember (ESimple typeName) funcName
      liftA2 (,) (f "encode") (f "decode")
    Imported md d     -> do
      typeName <- mkTypeCode d
      importedAlias <- mkGuguguImportAlias md
      let namespaced = ESimple importedAlias `EMember` typeName
          f p        = do
            funcName <- mkTypeFunc $ p <> dataName d
            pure $ EMember namespaced $ funcName
      liftA2 (,) (f "encode") (f "decode")
    Primitive _       ->
      let f ct = ESimple guguguCodecAlias `EMember` ct `EMember` T.toLower t
      in pure (f "Encoder", f "Decoder")

resolveForeign :: Data -> Maybe ((BindingIdentifier, Text), NamespaceName)
resolveForeign Data{..} = do
  foreignPragma <- Map.lookup thisTarget dataForeignMap
  let (importPath', name) = T.breakOnEnd "\"." foreignPragma
  let importPath = T.drop 1 . T.dropEnd 2 $ importPath'
      importName = "_gugugu_f_"
        <> (T.filter (/= '.') . T.replace "/" "_" $ importPath)
      qualName   = NamespaceName $ importName :| [name]
  pure ((importName, importPath), qualName)

resolveForeign' :: GuguguK r m
                => Data
                -> m ((BindingIdentifier, Text), NamespaceName)
resolveForeign' d@Data{..} = case resolveForeign d of
  Just v  -> pure v
  Nothing -> throwError $ printf
      "Type %s does not have foreign pragma" dataName

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

mkModuleValue :: GuguguK r m => Module -> m Expression
mkModuleValue Module{..} = withTransformer transModuleValue $ \f ->
  EArray [ESimple $ unsafeQuote $ f moduleName]

mkModuleType :: GuguguK r m => Module -> Text -> m Text
mkModuleType Module{..} suffix = withTransformer transModuleType $ \f ->
  f $ moduleName <> suffix

mkFuncCode :: GuguguK r m => Func -> m Text
mkFuncCode Func{..} = withTransformer transFuncCode $ \f ->
  f funcName

mkFuncValue :: GuguguK r m => Func -> m Expression
mkFuncValue Func{..} = withTransformer transFuncValue $ \f ->
  ESimple $ unsafeQuote $ f funcName

mkTypeFunc :: GuguguK r m => Text -> m Text
mkTypeFunc name = withTransformer transTypeFunc $ \f ->
  f name

mkTypeCode :: GuguguK r m => Data -> m Text
mkTypeCode Data{..} = withTransformer transTypeCode $ \f ->
  f dataName

mkFieldCode :: GuguguK r m => RecordField -> m Text
mkFieldCode RecordField{..} = withTransformer transFieldCode $ \f ->
  f recordFieldName

mkFieldValue :: GuguguK r m => RecordField -> m Expression
mkFieldValue RecordField{..} = withTransformer transFieldValue $ \f ->
  ESimple $ unsafeQuote $ f recordFieldName

mkEnumCode :: GuguguK r m => Text -> m Text
mkEnumCode name = withTransformer transEnumCode $ \f ->
  unsafeQuote $ f name

mkEnumValue :: GuguguK r m => Text -> m Expression
mkEnumValue name = withTransformer transEnumValue $ \f ->
  ESimple $ unsafeQuote $ f name


-- Utilities

thisTarget :: Text
thisTarget = "typescript"

guguguCodecAlias :: Text
guguguCodecAlias = "_gugugu_c"

guguguTransportAlias :: Text
guguguTransportAlias = "_gugugu_t"

mkGuguguImportAlias :: GuguguK r m => Module -> m Text
mkGuguguImportAlias Module{..} = pure $ "_gugugu_i_" <> moduleName

mkForeignCodecName :: GuguguK r m => Module -> Data -> m (Text, Text)
mkForeignCodecName Module{..} Data{..} = do
  let qName = if moduleName == "Foreign"
        then dataName else moduleName <> dataName
      f p   = mkTypeFunc $ p <> qName
  liftA2 (,) (f "encode") (f "decode")

nSimple :: Text -> NamespaceName
nSimple t = NamespaceName $ t :| []

eArrow1 :: Text -> Either Expression FunctionBody -> Expression
eArrow1 t body = EArrow ArrowFunction
  { afParams = [t]
  , afBody   = body
  }

eNeq :: Expression -> Expression -> Expression
l `eNeq` r = EBinary l "!==" r

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
