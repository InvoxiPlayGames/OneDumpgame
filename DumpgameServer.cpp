#include <iostream>
#pragma comment(lib, "Ws2_32.lib")
#define _WINSOCK_DEPRECATED_NO_WARNINGS
#include <WinSock2.h>
#include <ws2tcpip.h>

#pragma pack(push,1)
typedef struct _DumpgameDetail {
    DWORD dwFileAttributes;
    FILETIME ftLastWriteTime;
    UINT64 nFileSize;
    DWORD dwFilenameLength;
} DumpgameDetail;
#pragma pack(pop)

#define CHUNK_SIZE 0x1000000
char fileBuffer[0x1000000];

void handle_upload(SOCKET sock) {
    int r = 0;
    DumpgameDetail recentDetail = { 0 };
    char recentFilename[255] = { 0 };
    while (true) {
        memset(&recentDetail, 0, sizeof(DumpgameDetail));
        memset(recentFilename, 0, sizeof(recentFilename));
        r = recv(sock, (char *)&recentDetail, sizeof(DumpgameDetail), 0);
        if (r == sizeof(DumpgameDetail)) {
            r = recv(sock, recentFilename, recentDetail.dwFilenameLength, 0);
            if (r == recentDetail.dwFilenameLength) {
                printf("Recieving %s (%i bytes)...\n", recentFilename, recentDetail.nFileSize);
                if (recentFilename[1] == ':')
                    recentFilename[1] = 'x';
                if ((recentDetail.dwFileAttributes & 0x10) == 0x10) {
                    BOOL rb = CreateDirectoryA(recentFilename, NULL);
                }
                else {
                    HANDLE file = CreateFileA(recentFilename, GENERIC_READ | GENERIC_WRITE, 0, NULL, 2, FILE_ATTRIBUTE_NORMAL, NULL);
                    UINT64 totalReadBytes = 0;
                    int sizeToRead = CHUNK_SIZE;
                    DWORD numBytesWritten = 0;
                    while (totalReadBytes < recentDetail.nFileSize) {
                        if (recentDetail.nFileSize - totalReadBytes < CHUNK_SIZE)
                            sizeToRead = recentDetail.nFileSize - totalReadBytes;
                        else
                            sizeToRead = CHUNK_SIZE;
                        r = recv(sock, fileBuffer, sizeToRead, 0);
                        WriteFile(file, fileBuffer, r, &numBytesWritten, NULL);
                        totalReadBytes += numBytesWritten;
                    }
                    CloseHandle(file);
                }
            }
        }
        else {
            break;
        }
    }
    r = closesocket(sock);
}

int main()
{
    WSADATA data;
    int r = WSAStartup(WINSOCK_VERSION, &data);

    SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);

    struct addrinfo* result = NULL;
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    hints.ai_flags = AI_PASSIVE;
    r = getaddrinfo(NULL, "8126", &hints, &result);
    r = bind(sock, result->ai_addr, sizeof(hints));
    r = listen(sock, 5);

    struct sockaddr_in insock;
    int insocklen = sizeof(insock);
    printf("waiting for connection...\n");
    SOCKET accSock = accept(sock, (struct sockaddr*)&insock, &insocklen);

    char *ip = inet_ntoa(insock.sin_addr);
    printf("connection from %s accepted!\n", ip);

    handle_upload(accSock);

    closesocket(sock);

    return 0;
}
