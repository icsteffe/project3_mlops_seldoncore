FROM seldonio/seldon-core-s2i-python3:1.17.1

WORKDIR /app

COPY model-serving/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY exported_model /app/exported_model
COPY model-serving/Model.py .

ENV MODEL_NAME=Model

EXPOSE 8000

ENTRYPOINT ["python", "-m", "seldon_core.wrapper", "Model.py"]
