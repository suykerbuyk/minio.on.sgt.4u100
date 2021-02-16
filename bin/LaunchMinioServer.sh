ulimit -n 1000000
export MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:=admin}
export MINIO_SECRET_KEY=${MINIO_SECRET_KEY:=password}
export MINIO_ROOT_USER=${MINIO_ACCESS_KEY:=admin}
export MINIO_ROOT_PASSWORD=${MINIO_SECRET_KEY:=password}
export MINIO_CACHE_DRIVES=""
export MINIO_STORAGE_CLASS_STANDARD="EC:2"
        minio server			http://172.20.2.11:9000/minio_test/disk{001...032} 			http://172.20.2.13:9000/minio_test/disk{001...032} 			http://172.20.2.15:9000/minio_test/disk{001...032} 			http://172.20.2.17:9000/minio_test/disk{001...032} 			http://172.20.2.19:9000/minio_test/disk{001...032} 			http://172.20.2.41:9000/minio_test/disk{001...032} #2>&1 >>/var/log/minio.log
