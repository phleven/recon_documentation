import argparse
from typing import Tuple

from pyspark.sql import SparkSession


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="PySpark loader for interfaces.int_recon_mly_snapshot via stored procedure"
    )
    parser.add_argument("--host", required=True, help="PostgreSQL host")
    parser.add_argument("--port", type=int, default=5432, help="PostgreSQL port")
    parser.add_argument("--database", required=True, help="Database name")
    parser.add_argument("--user", required=True, help="Database user")
    parser.add_argument("--password", required=True, help="Database password")
    parser.add_argument("--recon-month", required=True, help="Recon month in YYYYMM format")
    parser.add_argument("--batch-run-id", required=True, type=int, help="Batch run ID")
    parser.add_argument(
        "--replace-month",
        default="true",
        choices=["true", "false"],
        help="Delete existing rows for month before loading",
    )
    parser.add_argument(
        "--sslmode",
        default="prefer",
        choices=["disable", "allow", "prefer", "require", "verify-ca", "verify-full"],
        help="PostgreSQL SSL mode",
    )
    parser.add_argument(
        "--app-name",
        default="biq-int-recon-mly-snapshot-loader",
        help="Spark application name",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Run a post-load validation summary for recon_month and batch_run_id",
    )
    return parser.parse_args()


def get_jdbc_url(host: str, port: int, database: str) -> str:
    return f"jdbc:postgresql://{host}:{port}/{database}"


def call_snapshot_loader(
    spark: SparkSession,
    jdbc_url: str,
    user: str,
    password: str,
    recon_month: str,
    batch_run_id: int,
    replace_month: bool,
    sslmode: str,
) -> Tuple[int, int]:
    jvm = spark._jvm

    try:
        jvm.java.lang.Class.forName("org.postgresql.Driver")
    except Exception as exc:
        raise RuntimeError(
            "PostgreSQL JDBC driver not found. Start spark with "
            "--packages org.postgresql:postgresql:42.7.4"
        ) from exc

    props = jvm.java.util.Properties()
    props.setProperty("user", user)
    props.setProperty("password", password)
    props.setProperty("sslmode", sslmode)

    conn = None
    stmt = None
    try:
        conn = jvm.java.sql.DriverManager.getConnection(jdbc_url, props)
        conn.setAutoCommit(False)

        # OUT params are 4 and 5 according to the procedure signature.
        stmt = conn.prepareCall(
            "{ call interfaces.sp_load_int_recon_mly_snapshot_counts(?, ?, ?, ?, ?) }"
        )
        stmt.setString(1, recon_month)
        stmt.setLong(2, int(batch_run_id))
        stmt.setBoolean(3, bool(replace_month))
        stmt.registerOutParameter(4, jvm.java.sql.Types.BIGINT)
        stmt.registerOutParameter(5, jvm.java.sql.Types.BIGINT)

        stmt.execute()
        inserted = int(stmt.getLong(4))
        updated = int(stmt.getLong(5))

        conn.commit()
        return inserted, updated
    except Exception:
        if conn is not None:
            conn.rollback()
        raise
    finally:
        if stmt is not None:
            stmt.close()
        if conn is not None:
            conn.close()


def run_validation(
    spark: SparkSession,
    jdbc_url: str,
    user: str,
    password: str,
    recon_month: str,
    batch_run_id: int,
    sslmode: str,
) -> None:
    query = f"""
    (
      SELECT
          recon_month,
          batch_run_id,
          count(*) AS row_count,
          round(100.0 * count(logical_id) / nullif(count(*),0), 2) AS logical_id_pct,
          round(100.0 * count(claim_num) / nullif(count(*),0), 2) AS claim_num_pct,
          round(100.0 * count(member_type) / nullif(count(*),0), 2) AS member_type_pct,
          round(100.0 * count(payroll_office_number) / nullif(count(*),0), 2) AS payroll_pct,
          round(100.0 * count(email) / nullif(count(*),0), 2) AS email_pct,
          round(100.0 * count(phone_num) / nullif(count(*),0), 2) AS phone_pct
      FROM interfaces.int_recon_mly_snapshot
      WHERE recon_month = '{recon_month}'
        AND batch_run_id = {int(batch_run_id)}
      GROUP BY recon_month, batch_run_id
    ) t
    """

    props = {
        "user": user,
        "password": password,
        "driver": "org.postgresql.Driver",
        "sslmode": sslmode,
    }

    df = spark.read.jdbc(url=jdbc_url, table=query, properties=props)
    print("Validation summary:")
    df.show(truncate=False)


def main() -> None:
    args = parse_args()

    replace_month = args.replace_month.lower() == "true"
    jdbc_url = get_jdbc_url(args.host, args.port, args.database)

    spark = (
        SparkSession.builder.appName(args.app_name)
        .config("spark.sql.session.timeZone", "UTC")
        .getOrCreate()
    )

    try:
        inserted, updated = call_snapshot_loader(
            spark=spark,
            jdbc_url=jdbc_url,
            user=args.user,
            password=args.password,
            recon_month=args.recon_month,
            batch_run_id=args.batch_run_id,
            replace_month=replace_month,
            sslmode=args.sslmode,
        )

        print("Stored procedure completed.")
        print(f"Inserted rows: {inserted}")
        print(f"Updated rows: {updated}")

        if args.validate:
            run_validation(
                spark=spark,
                jdbc_url=jdbc_url,
                user=args.user,
                password=args.password,
                recon_month=args.recon_month,
                batch_run_id=args.batch_run_id,
                sslmode=args.sslmode,
            )
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
