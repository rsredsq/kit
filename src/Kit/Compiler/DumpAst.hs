module Kit.Compiler.DumpAst where

import Control.Exception
import Control.Monad
import Data.List
import Data.Maybe
import Kit.Ast
import Kit.Compiler.Context
import Kit.Compiler.Module
import Kit.Compiler.TypedDecl
import Kit.Compiler.TypedExpr
import Kit.Error
import Kit.HashTable
import Kit.Log
import Kit.Parser
import Kit.Str

dumpModuleDecl ctx mod decl = do
  case decl of
    DeclFunction f -> do
      putStr $ "  function " ++ (s_unpack $ functionName f) ++ ": "
      if null $ functionArgs f
        then putStr "() -> "
        else do
          putStrLn "("
          forM_
            (functionArgs f)
            (\arg -> do
              t <- dumpCt ctx (argType arg)
              putStrLn $ "      " ++ s_unpack (argName arg) ++ ": " ++ t
            )
          putStr $ "    ) -> "
      rt <- dumpCt ctx (functionType f)
      putStrLn rt
      case functionBody f of
        Just x -> do
          out <- dumpAst ctx 2 x
          putStrLn out
        _ -> return ()
      putStrLn ""

    DeclVar v -> do
      t <- dumpCt ctx (varType v)
      putStrLn $ "  var " ++ (s_unpack $ varName v) ++ ": " ++ t ++ "\n"
      case varDefault v of
        Just x -> do
          out <- dumpAst ctx 2 x
          putStrLn out
        _ -> return ()

    DeclType t -> do
      putStrLn
        $  "  type "
        ++ (s_unpack $ showTypePath (modPath mod, typeName t))
      -- TODO: static methods
      forM_
        (typeStaticFields t)
        (\v -> do
          t <- dumpCt ctx (varType v)
          putStrLn $ "    static var " ++ (s_unpack $ varName v) ++ ": " ++ t
          case varDefault v of
            Just x -> do
              out <- dumpAst ctx 3 x
              putStrLn out
            _ -> return ()
        )
      -- TODO: instance methods
      case typeSubtype t of
        Struct { structFields = f } -> do
          forM_
            f
            (\v -> do
              t <- dumpCt ctx (varType v)
              putStrLn $ "    var " ++ (s_unpack $ varName v) ++ ": " ++ t
              case varDefault v of
                Just x -> do
                  out <- dumpAst ctx 3 x
                  putStrLn out
                _ -> return ()
            )
        Union { unionFields = f } -> do
          forM_
            f
            (\v -> do
              t <- dumpCt ctx (varType v)
              putStrLn $ "    var " ++ (s_unpack $ varName v) ++ ": " ++ t
              case varDefault v of
                Just x -> do
                  out <- dumpAst ctx 3 x
                  putStrLn out
                _ -> return ()
            )
        _ -> return ()
      putStrLn ""

    _ -> return ()

dumpAst :: CompileContext -> Int -> TypedExpr -> IO String
dumpAst ctx indent e@(TypedExpr { texpr = texpr, inferredType = t, tPos = pos })
  = do
    let dumpChild = dumpAst ctx (indent + 1)
    t' <- dumpCt ctx t
    let indented = (++) (take (indent * 2) $ repeat ' ')
    let f x = indented $ x ++ ": " ++ t'
    let i x children =
          (do
            children' <- mapM dumpChild children
            return $ intercalate "\n" $ (f x) : children'
          )
    case texpr of
      Block   x      -> i "{}" x
      Literal v      -> return $ f $ show v
      This           -> return $ f "this"
      Self           -> return $ f "Self"
      Identifier x n -> return $ f $ "identifier " ++ intercalate
        "."
        (map s_unpack n ++ [show x])
      PreUnop  op a -> i ("pre " ++ show op) [a]
      PostUnop op a -> i ("post " ++ show op) [a]
      Binop op a b  -> i ("binary " ++ show op) [a, b]
      For   a  b c  -> i ("for") [a, b, c]
      While a b     -> i ("while") [a, b]
      If a b c      -> i ("if") (catMaybes [Just a, Just b, c])
      Continue      -> return $ f "continue"
      Break         -> return $ f "break"
      Return     x  -> i "return" (catMaybes [x])
      -- Throw a
      -- Match a [MatchCase a] (Maybe a)
      InlineCall a  -> i "inline" [a]
      Field a id    -> i ("field " ++ show id) [a]
      StructInit (TypeStruct tp _) fields ->
        i ("struct " ++ s_unpack (showTypePath tp)) (map snd fields)
      EnumInit _ constructor fields ->
        i ("enum " ++ s_unpack constructor) fields
      ArrayAccess a b       -> i "array access" [a, b]
      Call        a args    -> i "call" (a : args)
      Cast        a _       -> i "cast" [a]
      -- TokenExpr [TokenClass]
      Unsafe       a        -> i "unsafe" [a]
      BlockComment _        -> return $ f "/** ... */"
      -- LexMacro Str [TokenClass]
      RangeLiteral a b      -> i "_ ... _" [a, b]
      VectorLiteral x       -> i "[]" x
      VarDeclaration id _ a -> i ("var " ++ show id) (catMaybes [a])
      Using u x -> i ("using " ++ show u) [x]
      _                     -> return $ f $ "??? " ++ show texpr

dumpCt :: CompileContext -> ConcreteType -> IO String
dumpCt ctx t = case t of
  TypeTypeVar i -> do
    info <- getTypeVar ctx i
    let
      tv =
        "type var #"
          ++ show i
          ++ (if null $ typeVarConstraints info
               then ""
               else
                 " ["
                 ++ intercalate
                      ", "
                      ( map (s_unpack . showTypePath . fst . fst)
                      $ typeVarConstraints info
                      )
                 ++ "]"
             )
    case typeVarValue info of
      Just t -> do
        t' <- dumpCt ctx t
        return $ tv ++ " => " ++ t'
      Nothing -> return tv
  _ -> return $ show t

