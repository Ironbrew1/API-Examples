! Build and run:  gfortran main.f90 -o main -lcurl && ./main
! Calls libcurl through ISO_C_BINDING; the request/response bodies are streamed through C FILE* handles.
module curl_bindings
  use, intrinsic :: iso_c_binding
  implicit none

  integer(c_int), parameter :: CURLOPT_WRITEDATA = 10001, CURLOPT_URL = 10002, CURLOPT_READDATA = 10009
  integer(c_int), parameter :: CURLOPT_HTTPHEADER = 10023, CURLOPT_TIMEOUT = 13, CURLOPT_POST = 47
  integer(c_int), parameter :: CURLOPT_POSTFIELDSIZE = 60, CURLINFO_RESPONSE_CODE = 2097154

  interface
    function curl_easy_init() bind(C, name="curl_easy_init")
      import :: c_ptr
      type(c_ptr) :: curl_easy_init
    end function

    ! curl_easy_setopt is variadic in C, so one binding per argument type.
    function setopt_long(handle, option, value) bind(C, name="curl_easy_setopt")
      import :: c_ptr, c_int, c_long
      integer(c_int) :: setopt_long
      type(c_ptr), value :: handle
      integer(c_int), value :: option
      integer(c_long), value :: value
    end function

    function setopt_ptr(handle, option, value) bind(C, name="curl_easy_setopt")
      import :: c_ptr, c_int
      integer(c_int) :: setopt_ptr
      type(c_ptr), value :: handle
      integer(c_int), value :: option
      type(c_ptr), value :: value
    end function

    function setopt_str(handle, option, value) bind(C, name="curl_easy_setopt")
      import :: c_ptr, c_int, c_char
      integer(c_int) :: setopt_str
      type(c_ptr), value :: handle
      integer(c_int), value :: option
      character(kind=c_char) :: value(*)
    end function

    function curl_easy_perform(handle) bind(C, name="curl_easy_perform")
      import :: c_ptr, c_int
      integer(c_int) :: curl_easy_perform
      type(c_ptr), value :: handle
    end function

    function curl_easy_getinfo(handle, info, value) bind(C, name="curl_easy_getinfo")
      import :: c_ptr, c_int, c_long
      integer(c_int) :: curl_easy_getinfo
      type(c_ptr), value :: handle
      integer(c_int), value :: info
      integer(c_long) :: value
    end function

    subroutine curl_easy_cleanup(handle) bind(C, name="curl_easy_cleanup")
      import :: c_ptr
      type(c_ptr), value :: handle
    end subroutine

    function curl_slist_append(list, string) bind(C, name="curl_slist_append")
      import :: c_ptr, c_char
      type(c_ptr) :: curl_slist_append
      type(c_ptr), value :: list
      character(kind=c_char) :: string(*)
    end function

    subroutine curl_slist_free_all(list) bind(C, name="curl_slist_free_all")
      import :: c_ptr
      type(c_ptr), value :: list
    end subroutine

    function fopen(path, mode) bind(C, name="fopen")
      import :: c_ptr, c_char
      type(c_ptr) :: fopen
      character(kind=c_char) :: path(*), mode(*)
    end function

    function fclose(stream) bind(C, name="fclose")
      import :: c_ptr, c_int
      integer(c_int) :: fclose
      type(c_ptr), value :: stream
    end function

    function fseek(stream, offset, whence) bind(C, name="fseek")
      import :: c_ptr, c_int, c_long
      integer(c_int) :: fseek
      type(c_ptr), value :: stream
      integer(c_long), value :: offset
      integer(c_int), value :: whence
    end function

    function c_ftell(stream) bind(C, name="ftell")
      import :: c_ptr, c_long
      integer(c_long) :: c_ftell
      type(c_ptr), value :: stream
    end function

    subroutine rewind(stream) bind(C, name="rewind")
      import :: c_ptr
      type(c_ptr), value :: stream
    end subroutine

    function fmemopen(buf, size, mode) bind(C, name="fmemopen")
      import :: c_ptr, c_size_t, c_char
      type(c_ptr) :: fmemopen
      type(c_ptr), value :: buf
      integer(c_size_t), value :: size
      character(kind=c_char) :: mode(*)
    end function
  end interface
end module curl_bindings

program main
  use curl_bindings
  implicit none

  character(len=*), parameter :: BASE_URL = "https://ironbrew1.com"
  character(len=*), parameter :: API_KEY = "IB1-APIKEYHERE"
  character(len=*), parameter :: INPUT_PATH = "input.lua"
  character(len=*), parameter :: OUTPUT_PATH = "output.lua"
  character(len=*), parameter :: QUERY = &
    "platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false"
  integer, parameter :: RETRY_DELAY = 5, MAX_WAIT = 240, MAX_FAILS = 3

  character(len=:), allocatable :: body, status_url, state
  integer :: code, elapsed, fails, wait
  type(c_ptr) :: stream
  integer(c_int) :: rc

  body = call_api(BASE_URL//"/obfuscate?"//QUERY, INPUT_PATH, code)
  if (.not. ok(code)) call fail("Unable to queue obfuscation: "//itoa(code))

  status_url = field(body, "statusUrl")
  print '(A)', "Obfuscation started with GUID: "//field(body, "uploadGuid")

  elapsed = 0
  fails = 0
  wait = 0

  do
    wait = wait + RETRY_DELAY
    call sleep(wait)
    elapsed = elapsed + wait

    body = call_api(BASE_URL//status_url, "", code)
    if (.not. ok(code)) then
      fails = fails + 1
      print '(A)', "Status check failed with status: "//itoa(code)//" ("//itoa(fails)//"/"//itoa(MAX_FAILS)//")"
      if (fails >= MAX_FAILS .or. elapsed >= MAX_WAIT) then
        call fail("Obfuscation failed (fails: "//itoa(fails)//" | elapsed time: "//itoa(elapsed)//")")
      end if
      cycle
    end if

    state = field(body, "status")

    if (state == "completed") then
      print '(A)', "Obfuscation completed in "//itoa(elapsed)//" seconds"
      stream = fopen(OUTPUT_PATH//c_null_char, "wb"//c_null_char)
      code = request(BASE_URL//field(body, "downloadUrl"), "", stream)
      rc = fclose(stream)
      if (.not. ok(code)) call fail("Download failed with status: "//itoa(code))
      print '(A)', "Saved obfuscated script to "//OUTPUT_PATH
      exit
    end if

    if (state == "failed" .or. elapsed >= MAX_WAIT) then
      call fail("Obfuscation failed (status: "//state//" | elapsed time: "//itoa(elapsed)//")")
    end if

    print '(A)', "Obfuscation is still in progress. Elapsed time: "//itoa(elapsed)// &
      " seconds. Checking again in "//itoa(RETRY_DELAY + wait)//" seconds."
  end do

contains

  logical function ok(status)
    integer, intent(in) :: status
    ok = status >= 200 .and. status < 300
  end function

  function itoa(n) result(s)
    integer, intent(in) :: n
    character(len=:), allocatable :: s
    character(len=20) :: tmp
    write (tmp, '(I0)') n
    s = trim(tmp)
  end function

  subroutine fail(message)
    character(len=*), intent(in) :: message
    write (0, '(A)') message
    call exit(1)
  end subroutine

  ! Pulls a string value out of a flat JSON object without needing a JSON library.
  function field(json, name) result(value)
    character(len=*), intent(in) :: json, name
    character(len=:), allocatable :: value
    integer :: k, a, b
    value = ""
    k = index(json, '"'//name//'"')
    if (k == 0) return
    a = index(json(k:), ":") + k - 1
    if (json(a+1:a+1) /= '"') return
    b = index(json(a+2:), '"')
    if (b == 0) return
    value = json(a+2:a+b)
  end function

  ! Sends one request (POSTs the contents of input_path if it is not empty) and
  ! streams the response body into `output`. Returns the HTTP status code.
  function request(url, input_path, output) result(code)
    character(len=*), intent(in) :: url, input_path
    type(c_ptr), intent(in) :: output
    integer :: code
    type(c_ptr) :: curl, headers, input
    integer(c_long) :: status, size
    integer(c_int) :: rc

    status = 0
    input = c_null_ptr
    curl = curl_easy_init()
    headers = curl_slist_append(c_null_ptr, "Key: "//API_KEY//c_null_char)
    headers = curl_slist_append(headers, "Content-Type: text/plain"//c_null_char)

    rc = setopt_str(curl, CURLOPT_URL, url//c_null_char)
    rc = setopt_ptr(curl, CURLOPT_HTTPHEADER, headers)
    rc = setopt_long(curl, CURLOPT_TIMEOUT, 120_c_long)
    rc = setopt_ptr(curl, CURLOPT_WRITEDATA, output)

    if (len(input_path) > 0) then
      input = fopen(input_path//c_null_char, "rb"//c_null_char)
      rc = fseek(input, 0_c_long, 2_c_int)
      size = c_ftell(input)
      call rewind(input)
      rc = setopt_long(curl, CURLOPT_POST, 1_c_long)
      rc = setopt_long(curl, CURLOPT_POSTFIELDSIZE, size)
      rc = setopt_ptr(curl, CURLOPT_READDATA, input)
    end if

    if (curl_easy_perform(curl) == 0) rc = curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, status)

    call curl_easy_cleanup(curl)
    call curl_slist_free_all(headers)
    if (len(input_path) > 0) rc = fclose(input)
    code = int(status)
  end function

  ! Like request, but returns the (small, JSON) response body as a string.
  function call_api(url, input_path, code) result(body)
    character(len=*), intent(in) :: url, input_path
    integer, intent(out) :: code
    character(len=:), allocatable :: body
    character(kind=c_char), target :: buf(65536)
    type(c_ptr) :: stream
    integer(c_int) :: rc
    integer :: n, i

    buf = c_null_char
    stream = fmemopen(c_loc(buf), 65536_c_size_t, "w"//c_null_char)
    code = request(url, input_path, stream)
    rc = fclose(stream)

    n = 0
    do while (n < size(buf))
      if (buf(n + 1) == c_null_char) exit
      n = n + 1
    end do
    allocate (character(len=n) :: body)
    do i = 1, n
      body(i:i) = buf(i)
    end do
  end function

end program main
