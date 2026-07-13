FROM golang:1.26-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath -ldflags="-s -w" \
    -o /out/icloud-hme .

FROM alpine:3.22

RUN apk add --no-cache ca-certificates \
    && addgroup -g 10001 app \
    && adduser -D -H -u 10001 -G app app

COPY --from=builder /out/icloud-hme /usr/local/bin/icloud-hme

USER 10001:10001
EXPOSE 8081

ENTRYPOINT ["icloud-hme"]
CMD ["-addr", ":8081", "-data", "/data"]
