FROM seldonio/seldon-core-s2i-python3:1.17.1

WORKDIR /app

COPY model-serving/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY exported_model /app/exported_model
COPY model-serving/Model.py .

ENV MODEL_NAME=Model
ENV PREDICTIVE_UNIT_SERVICE_PORT=9000
ENV PREDICTIVE_UNIT_METRICS_PORT=6000

EXPOSE 9000 9500 6000

# Use seldon-core-microservice with the class name (not filename)
# This starts the model server on the specified ports
CMD ["seldon-core-microservice", "Model", "--service-type", "MODEL"]
