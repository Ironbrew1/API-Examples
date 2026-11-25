{- cabal:
build-depends: base, bytestring, text, aeson, http-conduit
-}
{-# LANGUAGE OverloadedStrings #-}
-- Run with: cabal run Main.hs   (cabal 3.8+ script mode; dependencies are downloaded on first run)
module Main (main) where

import Control.Concurrent (threadDelay)
import Data.Aeson (Value (..), decode)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import Network.HTTP.Simple
import System.Exit (die)

baseUrl, apiKey, inputPath, outputPath, query :: String
baseUrl = "https://ironbrew1.com"
apiKey = "IB1-APIKEYHERE"
inputPath = "input.lua"
outputPath = "output.lua"
query = "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"

retryDelay, maxWait, maxFails :: Int
retryDelay = 5
maxWait = 240
maxFails = 3

-- Sends a request and returns the HTTP status code and body.
request :: String -> String -> Maybe BS.ByteString -> IO (Int, LBS.ByteString)
request verb path body = do
  base <- parseRequest (verb ++ " " ++ baseUrl ++ path)
  let withKey = setRequestHeader "Key" [BC.pack apiKey] base
      req = case body of
        Nothing -> withKey
        Just b -> setRequestHeader "Content-Type" ["text/plain"] (setRequestBodyLBS (LBS.fromStrict b) withKey)
  response <- httpLBS req
  pure (getResponseStatusCode response, getResponseBody response)

-- Reads a string field from a JSON object ("" if missing).
field :: String -> LBS.ByteString -> String
field name json = case decode json of
  Just (Object o) | Just (String s) <- KeyMap.lookup (Key.fromString name) o -> T.unpack s
  _ -> ""

ok :: Int -> Bool
ok code = code `div` 100 == 2

poll :: String -> Int -> Int -> Int -> IO ()
poll statusUrl elapsed0 fails0 wait0 = do
  let wait = wait0 + retryDelay
  threadDelay (wait * 1000000)
  let elapsed = elapsed0 + wait
  (code, body) <- request "GET" statusUrl Nothing
  if not (ok code)
    then do
      let fails = fails0 + 1
      putStrLn $ "Status check failed with status: " ++ show code ++ " (" ++ show fails ++ "/" ++ show maxFails ++ ")"
      if fails >= maxFails || elapsed >= maxWait
        then die $ "Obfuscation failed (fails: " ++ show fails ++ " | elapsed time: " ++ show elapsed ++ ")"
        else poll statusUrl elapsed fails wait
    else do
      let state = field "status" body
      if state == "completed"
        then do
          putStrLn $ "Obfuscation completed in " ++ show elapsed ++ " seconds"
          (downloadCode, script) <- request "GET" (field "downloadUrl" body) Nothing
          if not (ok downloadCode)
            then die $ "Download failed with status: " ++ show downloadCode
            else do
              LBS.writeFile outputPath script
              putStrLn $ "Saved obfuscated script to " ++ outputPath
        else
          if state == "failed" || elapsed >= maxWait
            then die $ "Obfuscation failed (status: " ++ state ++ " | elapsed time: " ++ show elapsed ++ ")"
            else do
              putStrLn $ "Obfuscation is still in progress. Elapsed time: " ++ show elapsed ++ " seconds. Checking again in " ++ show (retryDelay + wait) ++ " seconds."
              poll statusUrl elapsed fails0 wait

main :: IO ()
main = do
  source <- BS.readFile inputPath
  (code, body) <- request "POST" ("/obfuscate?" ++ query) (Just source)
  if not (ok code)
    then die $ "Unable to queue obfuscation: " ++ show code
    else do
      putStrLn $ "Obfuscation started with GUID: " ++ field "uploadGuid" body
      poll (field "statusUrl" body) 0 0 0
