FROM scratch
WORKDIR /app
COPY ./zig-out/bin/zig_socket /app/zig_socket
EXPOSE 9224  
CMD ["/app/zig_socket"]
