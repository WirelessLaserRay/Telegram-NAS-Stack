package telegram

import (
	"context"
	"io"
)

const (
	TypePhoto     = "photo"
	TypeVideo     = "video"
	TypeAudio     = "audio"
	TypeAnimation = "animation"
	TypeDocument  = "document"
)

type UploadRequest struct {
	Type     string
	ChatID   string
	Reader   io.Reader
	Filename string
	MIMEType string
	Caption  string
}

type UploadedFile struct {
	Type         string
	FileID       string
	FileUniqueID string
	MessageID    int64
	FileSize     int64
	MIMEType     string
}

type DownloadRequest struct {
	FileID string
	Offset int64
	Limit  int64
}

type Client interface {
	Upload(ctx context.Context, request UploadRequest) (UploadedFile, error)
	Download(ctx context.Context, request DownloadRequest) (io.ReadCloser, error)
}
