from prefect import flow, task
from concurrent.futures import ThreadPoolExecutor

@task
def log_payload(task_name: str, payload: dict):
    print(f"{task_name} received payload: {payload}")

@flow(name="helios-flow")
def helios_flow(payload: dict):
    log_payload("Helios", payload)

@flow(name="venus-flow")
def venus_flow(payload: dict):
    log_payload("Venus", payload)

@flow(name="regulus-flow")
def regulus_flow(payload: dict):
    log_payload("Regulus", payload)

@flow(name="parent-flow")
def parent_flow(payload: dict):
    # First, run helios_flow synchronously on the helios pool
    helios_flow(payload)

    # Then, run venus_flow and regulus_flow concurrently
    with ThreadPoolExecutor() as executor:
        future_venus = executor.submit(venus_flow, payload)
        future_regulus = executor.submit(regulus_flow, payload)
        # Wait for both to complete
        future_venus.result()
        future_regulus.result()

if __name__ == "__main__":
    import sys, json
    if len(sys.argv) < 2:
        print("Usage: python my_flow.py '<json_payload>'")
        sys.exit(1)
    payload = json.loads(sys.argv[1])
    parent_flow(payload)
