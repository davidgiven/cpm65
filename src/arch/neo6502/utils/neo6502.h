#pragma once

#define CP ((volatile uint8_t*)0xff00)

#define CP_GROUP    *(CP + 0)
#define CP_FUNCTION *(CP + 1)
#define CP_ERRNO    *(CP + 2)
#define CP_INFO     *(CP + 3)
#define CP_PARAM    (CP + 4)

#define GROUP_TTY              2
#define FUNC_TTY_READCH        1
#define FUNC_TTY_POLLCH        2
#define FUNC_TTY_WRITECH       6
#define FUNC_TTY_SETCURSOR     7
#define FUNC_TTY_GETSIZE       9
#define FUNC_TTY_INSERTLINE    10
#define FUNC_TTY_DELETELINE    11
#define FUNC_TTY_CLEAR         12
#define FUNC_TTY_GETCURSOR     13
#define FUNC_TTY_CLEARAREA     14
#define FUNC_TTY_SETCOLOURS    15
#define FUNC_TTY_REVERSECURSOR 16

#define GROUP_FILE	           3
#define FUNC_FILE_OPEN	       4
#define FUNC_FILE_CLOSE	       5
#define FUNC_FILE_SEEK         6
#define FUNC_FILE_TELL         7
#define FUNC_FILE_READH        8
#define FUNC_FILE_WRITEH       9
#define FUNC_FILE_GETSIZE      10
#define FUNC_FILE_SETSIZE      11
#define FUNC_FILE_RENAME       12
#define FUNC_FILE_DELETE       13
#define FUNC_FILE_STAT         16
#define FUNC_FILE_OPENDIR      17
#define FUNC_FILE_READDIR      18
#define FUNC_FILE_CLOSEDIR     19
#define FUNC_FILE_COPY         20

#define FIOMODE_RDONLY 	       0
#define FIOMODE_WRONLY         1
#define FIOMODE_RDWR           2
#define FIOMODE_RDWR_CREATE    3