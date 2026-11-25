--  Build and run:  gnatmake main.adb -largs -lcurl && ./main
--  Calls libcurl directly; the request/response bodies are streamed through C FILE* handles.
with Ada.Strings.Fixed;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Interfaces.C; use Interfaces.C;
with System;

procedure Main is

   Base_Url    : constant String := "https://ironbrew1.com";
   Api_Key     : constant String := "IB1-APIKEYHERE";
   Input_Path  : constant String := "input.lua";
   Output_Path : constant String := "output.lua";
   Query       : constant String :=
     "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false";

   Retry_Delay : constant := 5;
   Max_Wait    : constant := 240;
   Max_Fails   : constant := 3;

   CURLOPT_WRITEDATA       : constant int := 10001;
   CURLOPT_URL             : constant int := 10002;
   CURLOPT_READDATA        : constant int := 10009;
   CURLOPT_HTTPHEADER      : constant int := 10023;
   CURLOPT_TIMEOUT         : constant int := 13;
   CURLOPT_POST            : constant int := 47;
   CURLOPT_POSTFIELDSIZE   : constant int := 60;
   CURLINFO_RESPONSE_CODE  : constant int := 2097154;

   function Easy_Init return System.Address
     with Import, Convention => C, External_Name => "curl_easy_init";
   --  curl_easy_setopt is variadic in C, so one binding per argument type.
   function Setopt_Long (Handle : System.Address; Option : int; Value : long) return int
     with Import, Convention => C, External_Name => "curl_easy_setopt";
   function Setopt_Ptr (Handle : System.Address; Option : int; Value : System.Address) return int
     with Import, Convention => C, External_Name => "curl_easy_setopt";
   function Setopt_Str (Handle : System.Address; Option : int; Value : char_array) return int
     with Import, Convention => C, External_Name => "curl_easy_setopt";
   function Easy_Perform (Handle : System.Address) return int
     with Import, Convention => C, External_Name => "curl_easy_perform";
   function Easy_Getinfo (Handle : System.Address; Info : int; Value : in out long) return int
     with Import, Convention => C, External_Name => "curl_easy_getinfo";
   procedure Easy_Cleanup (Handle : System.Address)
     with Import, Convention => C, External_Name => "curl_easy_cleanup";
   function Slist_Append (List : System.Address; Text : char_array) return System.Address
     with Import, Convention => C, External_Name => "curl_slist_append";
   procedure Slist_Free_All (List : System.Address)
     with Import, Convention => C, External_Name => "curl_slist_free_all";
   function Fopen (Path : char_array; Mode : char_array) return System.Address
     with Import, Convention => C, External_Name => "fopen";
   function Fclose (Stream : System.Address) return int
     with Import, Convention => C, External_Name => "fclose";
   function Fseek (Stream : System.Address; Offset : long; Whence : int) return int
     with Import, Convention => C, External_Name => "fseek";
   function Ftell (Stream : System.Address) return long
     with Import, Convention => C, External_Name => "ftell";
   procedure Rewind (Stream : System.Address)
     with Import, Convention => C, External_Name => "rewind";
   function Fmemopen (Buf : System.Address; Size : size_t; Mode : char_array) return System.Address
     with Import, Convention => C, External_Name => "fmemopen";

   use type System.Address;

   function Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   function Ok (Code : Integer) return Boolean is (Code in 200 .. 299);

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Message);
      GNAT.OS_Lib.OS_Exit (1);
   end Fail;

   --  Pulls a string value out of a flat JSON object without needing a JSON library.
   function Field (Json, Name : String) return String is
      use Ada.Strings.Fixed;
      Key    : constant String := '"' & Name & '"';
      K      : constant Natural := Index (Json, Key);
      Colon  : Natural;
   begin
      if K = 0 then
         return "";
      end if;
      Colon := Index (Json, ":", K);
      if Colon = 0 or else Colon = Json'Last or else Json (Colon + 1) /= '"' then
         return "";
      end if;
      declare
         Close : constant Natural := Index (Json, """", Colon + 2);
      begin
         return (if Close = 0 then "" else Json (Colon + 2 .. Close - 1));
      end;
   end Field;

   --  Sends one request (POSTs the contents of Input if it is not empty) and streams the
   --  response body into Output. Returns the HTTP status code.
   function Request (Url : String; Input_File : String; Output : System.Address) return Integer is
      Handle  : constant System.Address := Easy_Init;
      Headers : System.Address := System.Null_Address;
      Input   : System.Address := System.Null_Address;
      Status  : long := 0;
      Size    : long;
      Rc      : int;
   begin
      Headers := Slist_Append (Headers, To_C ("Key: " & Api_Key));
      Headers := Slist_Append (Headers, To_C ("Content-Type: text/plain"));

      Rc := Setopt_Str (Handle, CURLOPT_URL, To_C (Url));
      Rc := Setopt_Ptr (Handle, CURLOPT_HTTPHEADER, Headers);
      Rc := Setopt_Long (Handle, CURLOPT_TIMEOUT, 120);
      Rc := Setopt_Ptr (Handle, CURLOPT_WRITEDATA, Output);

      if Input_File /= "" then
         Input := Fopen (To_C (Input_File), To_C ("rb"));
         Rc := Fseek (Input, 0, 2);
         Size := Ftell (Input);
         Rewind (Input);
         Rc := Setopt_Long (Handle, CURLOPT_POST, 1);
         Rc := Setopt_Long (Handle, CURLOPT_POSTFIELDSIZE, Size);
         Rc := Setopt_Ptr (Handle, CURLOPT_READDATA, Input);
      end if;

      if Easy_Perform (Handle) = 0 then
         Rc := Easy_Getinfo (Handle, CURLINFO_RESPONSE_CODE, Status);
      end if;

      Easy_Cleanup (Handle);
      Slist_Free_All (Headers);
      if Input /= System.Null_Address then
         Rc := Fclose (Input);
      end if;
      return Integer (Status);
   end Request;

   --  Like Request, but returns the (small, JSON) response body as a string.
   procedure Call_Api (Url, Input_File : String; Code : out Integer; Body_Text : out String;
                       Last : out Natural)
   is
      Buf    : aliased char_array (0 .. 65535) := (others => nul);
      Stream : constant System.Address := Fmemopen (Buf'Address, 65536, To_C ("w"));
      Rc     : int;
   begin
      Code := Request (Url, Input_File, Stream);
      Rc := Fclose (Stream);
      declare
         Text : constant String := To_Ada (Buf);
      begin
         Last := Body_Text'First + Text'Length - 1;
         Body_Text (Body_Text'First .. Last) := Text;
      end;
   end Call_Api;

   Json    : String (1 .. 65536);
   Last    : Natural;
   Code    : Integer;
   Elapsed : Integer := 0;
   Fails   : Integer := 0;
   Wait    : Integer := 0;
   Rc      : int;

begin
   Call_Api (Base_Url & "/obfuscate?" & Query, Input_Path, Code, Json, Last);
   if not Ok (Code) then
      Fail ("Unable to queue obfuscation: " & Img (Code));
   end if;

   declare
      Status_Url : constant String := Field (Json (1 .. Last), "statusUrl");
   begin
      Ada.Text_IO.Put_Line ("Obfuscation started with GUID: " & Field (Json (1 .. Last), "uploadGuid"));

      loop
         Wait := Wait + Retry_Delay;
         delay Duration (Wait);
         Elapsed := Elapsed + Wait;

         Call_Api (Base_Url & Status_Url, "", Code, Json, Last);
         if not Ok (Code) then
            Fails := Fails + 1;
            Ada.Text_IO.Put_Line ("Status check failed with status: " & Img (Code)
                                  & " (" & Img (Fails) & "/" & Img (Max_Fails) & ")");
            if Fails >= Max_Fails or else Elapsed >= Max_Wait then
               Fail ("Obfuscation failed (fails: " & Img (Fails) & " | elapsed time: " & Img (Elapsed) & ")");
            end if;
         else
            declare
               State : constant String := Field (Json (1 .. Last), "status");
            begin
               if State = "completed" then
                  Ada.Text_IO.Put_Line ("Obfuscation completed in " & Img (Elapsed) & " seconds");
                  declare
                     Output : constant System.Address := Fopen (To_C (Output_Path), To_C ("wb"));
                  begin
                     Code := Request (Base_Url & Field (Json (1 .. Last), "downloadUrl"), "", Output);
                     Rc := Fclose (Output);
                  end;
                  if not Ok (Code) then
                     Fail ("Download failed with status: " & Img (Code));
                  end if;
                  Ada.Text_IO.Put_Line ("Saved obfuscated script to " & Output_Path);
                  exit;
               end if;

               if State = "failed" or else Elapsed >= Max_Wait then
                  Fail ("Obfuscation failed (status: " & State & " | elapsed time: " & Img (Elapsed) & ")");
               end if;

               Ada.Text_IO.Put_Line ("Obfuscation is still in progress. Elapsed time: " & Img (Elapsed)
                                     & " seconds. Checking again in " & Img (Retry_Delay + Wait) & " seconds.");
            end;
         end if;
      end loop;
   end;
end Main;
